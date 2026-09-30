#include <jni.h>

#include <cstring>
#include <new>
#include <string>

#include "qfli_py_bridge.h"

namespace {

void ThrowJava(JNIEnv *env, const char *type, const char *message)
{
    jclass exception = env->FindClass(type);
    if (exception != nullptr) {
        env->ThrowNew(exception, message);
        env->DeleteLocalRef(exception);
    }
}

bool ReadUtf8(JNIEnv *env, jbyteArray value, std::string *out)
{
    if (value == nullptr) {
        ThrowJava(env, "java/lang/IllegalArgumentException", "Missing UTF-8 argument");
        return false;
    }
    jsize length = env->GetArrayLength(value);
    out->resize(static_cast<size_t>(length));
    if (length > 0) {
        env->GetByteArrayRegion(value, 0, length,
            reinterpret_cast<jbyte *>(&(*out)[0]));
    }
    if (env->ExceptionCheck())
        return false;
    if (out->find('\0') != std::string::npos) {
        ThrowJava(env, "java/lang/IllegalArgumentException", "Embedded NUL is unsupported");
        return false;
    }
    return true;
}

jbyteArray Utf8Bytes(JNIEnv *env, const char *text)
{
    if (text == nullptr)
        return nullptr;
    jsize length = static_cast<jsize>(strlen(text));
    jbyteArray result = env->NewByteArray(length);
    if (result != nullptr && length > 0) {
        env->SetByteArrayRegion(result, 0, length,
            reinterpret_cast<const jbyte *>(text));
    }
    return result;
}

struct RunResult {
    QfliPyRunResult value;
    ~RunResult() { qfli_py_result_free(&value); }
};

}  // namespace

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_azurekiln_qfli_pyflow_QfliPyNative_nativeVersion(JNIEnv *env, jobject)
{
    return Utf8Bytes(env, qfli_py_version());
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_azurekiln_qfli_pyflow_QfliPyNative_nativeRun(
    JNIEnv *env, jobject, jbyteArray source, jbyteArray stdin_text, jint heap_kb,
    jbyteArray project_dir, jbyteArray entry_file, jboolean compile_only)
{
    try {
        std::string source_text, input_text, project_path, entry_path;
        if (!ReadUtf8(env, source, &source_text)
            || !ReadUtf8(env, stdin_text, &input_text)
            || !ReadUtf8(env, project_dir, &project_path)
            || !ReadUtf8(env, entry_file, &entry_path))
            return nullptr;

        // Byte arrays avoid JNI's modified UTF-8, which corrupts non-BMP source/input.
        jclass type = env->FindClass("com/azurekiln/qfli/pyflow/QfliPyNativeResult");
        if (type == nullptr)
            return nullptr;
        jmethodID constructor = env->GetMethodID(type, "<init>", "(I[B[BZ)V");
        if (constructor == nullptr)
            return nullptr;

        RunResult raw{qfli_py_run(source_text.c_str(), input_text.c_str(), heap_kb,
            project_path.c_str(), entry_path.c_str(), compile_only ? 1 : 0)};
        jbyteArray output = Utf8Bytes(env, raw.value.output);
        if (env->ExceptionCheck())
            return nullptr;
        jbyteArray error = Utf8Bytes(env, raw.value.error);
        if (env->ExceptionCheck())
            return nullptr;
        return env->NewObject(type, constructor, static_cast<jint>(raw.value.exit_code),
            output, error, static_cast<jboolean>(raw.value.truncated != 0));
    } catch (const std::bad_alloc &) {
        ThrowJava(env, "java/lang/IllegalStateException", "Unable to allocate native Python arguments");
        return nullptr;
    }
}
