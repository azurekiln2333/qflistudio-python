/*
 * NAPI 外壳：把 qfli_py_execute() 暴露给 ArkTS。
 *
 * 这一层刻意做得很薄——只负责在 ArkTS 和纯 C 之间搬数据，不掺任何逻辑，
 * 因为它是整条链路里唯一没法用 Dart 测试覆盖的部分。任何「聪明」的处理
 * 放在这里都会变成上真机才能发现的问题。
 *
 * 与 Android JNI 对等的能力：
 *
 *   createCancel() -> number        创建一个取消 token（C 堆指针，用 number 传）
 *   cancel(token)                   从任意线程置位取消标志（C 侧是 atomic）
 *   freeCancel(token)               运行结束后释放 token
 *   run(..., token, artifact, mpy) -> Promise<outcome>
 *                                   异步入队，VM 跑在 NAPI worker 线程上
 *   version() -> string
 *
 * 为什么 run 必须异步：C VM 是一次同步调用，跑 `while True: pass` 时不会返回。
 * 如果直接在 ArkTS 线程上同步调，cancel 这一次 MethodChannel 回调根本没机会执行，
 * 「停止」按钮就是假的。NAPI 的 async work 把 VM 放到自己的 worker 线程，
 * ArkTS 线程继续处理 cancel；而 C 侧的取消标志本来就是原子的，跨线程置位安全，
 * VM 状态只在 worker 里被触碰（C 侧还有一把全局 mutex 兜底）。
 *
 * 早期版本只导出同步的 run(source, stdin, heapKb, projectPath, entryFile, compileOnly)。
 * ArkTS 侧现在统一用新的异步签名，兼容性由 ArkTS 那层保证（它先探测能力）。
 */
#include "napi/native_api.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>

#include "qfli_py_bridge.h"

namespace {

/* 读一个字符串参数；不是字符串或不存在时返回 false。 */
bool GetStringArg(napi_env env, napi_value value, std::string *out)
{
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok)
        return false;
    if (type != napi_string)
        return false;

    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok)
        return false;

    std::string buffer(length + 1, '\0');
    if (length > 0)
    {
        if (napi_get_value_string_utf8(env, value, &buffer[0], length + 1, &length) != napi_ok)
            return false;
    }
    buffer.resize(length);
    /*
     * 实际 NUL 字符不能过 C 边界：C API 收 const char*，会在这里静默截断，
     * 用户看到的是“源码只跑了一半”这种最难查的错。Android JNI 和桌面 FFI
     * 都已经是拒绝语义，这里必须一致。
     */
    if (buffer.find('\0') != std::string::npos)
        return false;
    *out = buffer;
    return true;
}

bool GetIntArg(napi_env env, napi_value value, int *out)
{
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok)
        return false;
    if (type != napi_number)
        return false;
    /*
     * 不能用 napi_get_value_int32：它对小数/NaN/Infinity/超范围的值会截断、
     * 环绕或给出未定义结果（heapKb=2^32 变成 0 = “用默认堆”，看起来能跑但
     * 堆大小不是用户要的）。napi_get_value_int64 同样会把 0.5 截成 0、把 NaN
     * 变成 0。所以先取 double，再显式判 isfinite / 是否为整数 / 范围。
     *
     * 下界是 0：heapKb 是 GC 堆大小（KB），传负数没有意义；C 侧的 0 = 用默认值。
     * 上界 INT32_MAX 与 C 的 int 参数以及 FFI 的 32 位校验一致。
     */
    double number = 0;
    if (napi_get_value_double(env, value, &number) != napi_ok)
        return false;
    if (!std::isfinite(number))
        return false;
    if (number != std::trunc(number))
        return false;
    if (number < 0.0 || number > static_cast<double>(INT32_MAX))
        return false;
    *out = static_cast<int>(number);
    return true;
}

/*
 * 读取消 token。
 *
 * token 是 C 堆上 QfliPyCancel* 的地址，**会被解引用**：Execute 把它交给
 * qfli_py_execute，Cancel/FreeCancel 分别调 qfli_py_cancel_request /
 * qfli_py_cancel_free，三者都对它做指针运算并访问其内存。所以它不是
 * “只比较的标记值”，而是一个会被当作真实指针使用的地址。
 *
 * 因此这里的定位是**最低限度畸形输入防御**，不是安全边界：只有 ArkTS 侧
 * registry 里由 qfli_py_cancel_create 分配的 token 才应传进来。本函数只保证
 * 传进来的是一个有限的、整数的、非负的、在 JS safe integer（2^53-1）内的值，
 * 把 NaN/Infinity/小数/负值这些一眼就不可能是本报分配地址的参数挡在入队前，
 * 避免它们以“取消无效”或更糟的形式在别处表现。
 *
 * 不用 std::numeric_limits<int64_t> 而用 JS 的 2^53-1：NAPI 传进来之前
 * 已经过了一遍 JS number，超出这个范围的值在 JS 侧就已经丢精度了。
 * 下界是 0：0 是“无可取消 session”的约定值；负值永远不可能是本报地址。
 */
bool GetInt64Arg(napi_env env, napi_value value, int64_t *out)
{
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok)
        return false;
    if (type != napi_number)
        return false;
    double number = 0;
    if (napi_get_value_double(env, value, &number) != napi_ok)
        return false;
    if (!std::isfinite(number))
        return false;
    if (number != std::trunc(number))
        return false;
    constexpr double kMaxSafeInteger = 9007199254740991.0; /* 2^53 - 1 */
    if (number < 0.0 || number > kMaxSafeInteger)
        return false;
    *out = static_cast<int64_t>(number);
    return true;
}

bool GetBoolArg(napi_env env, napi_value value, bool *out)
{
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok)
        return false;
    if (type != napi_boolean)
        return false;
    return napi_get_value_bool(env, value, out) == napi_ok;
}

napi_value MakeString(napi_env env, const char *text)
{
    napi_value value = nullptr;
    if (text == nullptr)
    {
        napi_get_null(env, &value);
        return value;
    }
    napi_create_string_utf8(env, text, NAPI_AUTO_LENGTH, &value);
    return value;
}

/*
 * 一次异步执行的上下文。
 *
 * 生命周期：Run() 里 new，Execute() 在 worker 线程上填结果，Complete() 回主线程
 * 转成 JS 对象后 delete。token 由 ArkTS 侧持有并在完成后 freeCancel，
 * 这样「运行中取消」和「完成后再取消」都落在同一个所有权规则里，和 Android
 * 的 RunSession 一致。
 */
struct RunWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;

    std::string source;
    std::string stdin_text;
    std::string project_path;
    std::string entry_file;
    std::string artifact_output;
    std::string bytecode_file;
    int heap_kb = 0;
    bool compile_only = false;
    QfliPyCancel *token = nullptr;

    QfliPyRunResult result = {};
};

void Execute(napi_env env, void *data)
{
    (void)env;
    RunWork *work = static_cast<RunWork *>(data);
    /* qfli_py_execute 会在 worker 线程上跑，token 是跨线程可见的原子标志。 */
    work->result = qfli_py_execute(
        work->source.c_str(),
        work->stdin_text.empty() ? nullptr : work->stdin_text.c_str(),
        work->heap_kb,
        work->project_path.c_str(),
        work->entry_file.c_str(),
        work->compile_only ? 1 : 0,
        work->token,
        work->artifact_output.empty() ? nullptr : work->artifact_output.c_str(),
        work->bytecode_file.empty() ? nullptr : work->bytecode_file.c_str());
}

void Complete(napi_env env, napi_status status, void *data)
{
    RunWork *work = static_cast<RunWork *>(data);
    if (status == napi_ok)
    {
        napi_value outcome = nullptr;
        napi_create_object(env, &outcome);

        napi_value exitCode = nullptr;
        napi_create_int32(env, work->result.exit_code, &exitCode);
        napi_set_named_property(env, outcome, "exitCode", exitCode);

        napi_set_named_property(env, outcome, "output",
            MakeString(env, work->result.output));
        napi_set_named_property(env, outcome, "error",
            MakeString(env, work->result.error));

        napi_value truncated = nullptr;
        napi_get_boolean(env, work->result.truncated != 0, &truncated);
        napi_set_named_property(env, outcome, "truncated", truncated);

        napi_resolve_deferred(env, work->deferred, outcome);
    }
    else
    {
        napi_value message = nullptr;
        napi_create_string_utf8(env, "Python 执行任务被取消或失败", NAPI_AUTO_LENGTH,
            &message);
        napi_reject_deferred(env, work->deferred, message);
    }

    /* 引擎缓冲在这里释放；token 由 ArkTS 侧在 run 完成后 freeCancel。 */
    qfli_py_result_free(&work->result);
    napi_delete_async_work(env, work->work);
    delete work;
}

/*
 * run(source, stdin, heapKb, projectPath, entryFile, compileOnly,
 *     token, artifactOutput, bytecodeFile) -> Promise<outcome>
 */
napi_value Run(napi_env env, napi_callback_info info)
{
    size_t argc = 9;
    napi_value argv[9] = {nullptr};
    napi_value thisArg = nullptr;

    if (napi_get_cb_info(env, info, &argc, argv, &thisArg, nullptr) != napi_ok)
        return nullptr;

    RunWork *work = new RunWork();

    if (argc < 1 || !GetStringArg(env, argv[0], &work->source))
    {
        delete work;
        napi_throw_type_error(env, nullptr,
            "run(): source 必须是不含 NUL 的字符串");
        return nullptr;
    }
    /*
     * 可选参数一旦**给了**就必须合法：给了非字符串/非数字还默默用默认值，
     * 会让调用方以为参数生效了（比如 artifactOutput 拼错了类型→编译产物没写），
     * 最后以“编译成功但找不到 .mpy”的形式在别处爆。宁可在这里明确报错。
     */
    if (argc >= 2 && !GetStringArg(env, argv[1], &work->stdin_text))
    {
        delete work;
        napi_throw_type_error(env, nullptr, "run(): stdin 必须是不含 NUL 的字符串");
        return nullptr;
    }
    if (argc >= 3 && !GetIntArg(env, argv[2], &work->heap_kb))
    {
        delete work;
        napi_throw_range_error(env, nullptr,
            "run(): heapKb 必须是 32 位整数");
        return nullptr;
    }
    if (argc >= 4 && !GetStringArg(env, argv[3], &work->project_path))
    {
        delete work;
        napi_throw_type_error(env, nullptr,
            "run(): projectPath 必须是不含 NUL 的字符串");
        return nullptr;
    }
    if (argc >= 5 && !GetStringArg(env, argv[4], &work->entry_file))
    {
        delete work;
        napi_throw_type_error(env, nullptr,
            "run(): entryFile 必须是不含 NUL 的字符串");
        return nullptr;
    }
    if (argc >= 6 && !GetBoolArg(env, argv[5], &work->compile_only))
    {
        delete work;
        napi_throw_type_error(env, nullptr, "run(): compileOnly 必须是布尔值");
        return nullptr;
    }
    if (argc >= 7)
    {
        int64_t token = 0;
        if (!GetInt64Arg(env, argv[6], &token))
        {
            delete work;
            napi_throw_type_error(env, nullptr, "run(): token 必须是整数");
            return nullptr;
        }
        work->token = reinterpret_cast<QfliPyCancel *>(static_cast<intptr_t>(token));
    }
    if (argc >= 8 && !GetStringArg(env, argv[7], &work->artifact_output))
    {
        delete work;
        napi_throw_type_error(env, nullptr,
            "run(): artifactOutput 必须是不含 NUL 的字符串");
        return nullptr;
    }
    if (argc >= 9 && !GetStringArg(env, argv[8], &work->bytecode_file))
    {
        delete work;
        napi_throw_type_error(env, nullptr,
            "run(): bytecodeFile 必须是不含 NUL 的字符串");
        return nullptr;
    }

    work->env = env;
    napi_value promise = nullptr;
    if (napi_create_promise(env, &work->deferred, &promise) != napi_ok)
    {
        delete work;
        napi_throw_error(env, nullptr, "run(): 无法创建 Promise");
        return nullptr;
    }

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "qfli_py_run", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(env, nullptr, resourceName, Execute, Complete,
            work, &work->work) != napi_ok)
    {
        napi_reject_deferred(env, work->deferred, MakeString(env, "无法创建执行任务"));
        delete work;
        return promise;
    }
    if (napi_queue_async_work(env, work->work) != napi_ok)
    {
        napi_delete_async_work(env, work->work);
        napi_reject_deferred(env, work->deferred, MakeString(env, "无法入队执行任务"));
        delete work;
        return promise;
    }
    return promise;
}

/* createCancel() -> number  （C 堆上的 token 地址；0 表示分配失败） */
napi_value CreateCancel(napi_env env, napi_callback_info info)
{
    (void)info;
    QfliPyCancel *token = qfli_py_cancel_create();
    napi_value result = nullptr;
    napi_create_int64(env, static_cast<int64_t>(reinterpret_cast<intptr_t>(token)),
        &result);
    return result;
}

/* cancel(token) -> void  （只置位原子标志，不触碰 VM 状态） */
napi_value Cancel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok
        || argc < 1)
    {
        return nullptr;
    }
    int64_t token = 0;
    if (GetInt64Arg(env, argv[0], &token))
    {
        qfli_py_cancel_request(
            reinterpret_cast<QfliPyCancel *>(static_cast<intptr_t>(token)));
    }
    return nullptr;
}

/* freeCancel(token) -> void */
napi_value FreeCancel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok
        || argc < 1)
    {
        return nullptr;
    }
    int64_t token = 0;
    if (GetInt64Arg(env, argv[0], &token))
    {
        qfli_py_cancel_free(
            reinterpret_cast<QfliPyCancel *>(static_cast<intptr_t>(token)));
    }
    return nullptr;
}

/*
 * version() -> string
 *
 * 返回内嵌 MicroPython 的版本，形如 "1.24.1 (ecfdd5d)"。
 *
 * 这个函数不需要初始化 VM，也不碰 GC 堆——纯粹把编译期常量搬出去，所以可以
 * 在任何时候安全地调，包括 App 刚起来、还没跑过任何 Python 代码的时候。
 * 用途是自证后端身份：版本号和 commit hash 来自上游头文件，改不了。
 */
napi_value Version(napi_env env, napi_callback_info info)
{
    (void)info;
    return MakeString(env, qfli_py_version());
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        {"run", nullptr, Run, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createCancel", nullptr, CreateCancel, nullptr, nullptr, nullptr,
         napi_default, nullptr},
        {"cancel", nullptr, Cancel, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"freeCancel", nullptr, FreeCancel, nullptr, nullptr, nullptr,
         napi_default, nullptr},
        {"version", nullptr, Version, nullptr, nullptr, nullptr, napi_default,
         nullptr},
    };
    napi_define_properties(
        env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

}  // namespace

static napi_module qfliPyNativeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "qfli_py",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterQfliPyNativeModule(void)
{
    napi_module_register(&qfliPyNativeModule);
}
