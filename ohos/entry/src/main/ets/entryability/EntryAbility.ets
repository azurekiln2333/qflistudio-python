
import {
  FlutterAbility,
  FlutterEngine,
  MethodChannel,
  MethodCall,
  MethodResult,
} from '@ohos/flutter_ohos';
import { authentication } from '@kit.AccountKit';
import { systemShare } from '@kit.ShareKit';
import { common, Want, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { registerQfliPyNativeChannel } from '../plugins/QfliPyNative';
import { handlePickerCall, isPickerMethod } from './PickerBridge';

const CHANNEL_PLATFORM = 'qflistudio/platform';
const CHANNEL_HUAWEI = 'qflistudio/huawei_account';
// Standalone Python has no account, remote agreement, or browser workflow.
const OFFLINE_ONLY = true;
const EVENT_STARTUP_PROGRESS = 'EVENT_STARTUP_PROGRESS';
const STARTUP_PROGRESS_KEY = 'pyflowStartupProgress';

export default class EntryAbility extends FlutterAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 启动遮罩消失后、Flutter 首帧渲染前，引擎初始化期间窗口会露出
    // 默认白底。窗口底色与 Flutter 的 MD3 surface 保持一致。
    try {
      const isDark = this.context.config?.colorMode ===
        ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      windowStage.getMainWindowSync().setWindowBackgroundColor(
        isDark ? '#FF111418' : '#FFF8F9FF',
      );
    } catch (e) {
      // 设置失败不影响启动（仅深色模式可能出现短暂白闪）。
    }
    super.onWindowStageCreate(windowStage);
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)

    // Python 执行后端：libqfli_py.so（内嵌 MicroPython）+ NAPI。
    // 没打进 .so 时这里编不过——ArkTS 的 import 是构建期解析的，
    // 见 native/README.md 的「启用原生后端」一节。
    registerQfliPyNativeChannel(flutterEngine)

    const abilityContext = this.context as common.UIAbilityContext;
    AppStorage.setOrCreate(STARTUP_PROGRESS_KEY, 0);

    // Local platform capabilities; reject remote entry points in this edition.
    const platformChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(),
      CHANNEL_PLATFORM,
    );
    platformChannel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult): void {
        if (OFFLINE_ONLY && (call.method === 'openAgreement' || call.method === 'openUrl')) {
          result.error('OFFLINE_ONLY', '独立离线版不提供远程协议或浏览器入口', null);
          return;
        }
        if (call.method === 'startupProgress') {
          const progress = call.argument('progress') as number;
          if (typeof progress === 'number' && Number.isFinite(progress)) {
            const boundedProgress = Math.max(0, Math.min(1, progress));
            AppStorage.setOrCreate(STARTUP_PROGRESS_KEY, boundedProgress);
            abilityContext.eventHub.emit(EVENT_STARTUP_PROGRESS, boundedProgress);
            result.success(null);
          } else {
            result.error('INVALID_PROGRESS', 'Startup progress must be a finite number', null);
          }
        } else if (call.method === 'openUrl') {
          const url = call.argument('url') as string;
          const want: Want = {
            action: 'ohos.want.action.viewData',
            uri: url,
          };
          abilityContext.startAbility(want)
            .then(() => {
              result.success(null);
            })
            .catch((err: BusinessError) => {
              result.error(`${err.code}`, `${err.message}`, null);
            });
        } else if (call.method === 'shareText') {
          // 系统分享面板（Share Kit）：纯文本分享。
          const title = call.argument('title') as string;
          const text = call.argument('text') as string;
          const record: systemShare.SharedRecord = {
            utd: 'general.plain-text',
            content: text,
            title: title,
          };
          const data = new systemShare.SharedData(record);
          const controller = new systemShare.ShareController(data);
          const options: systemShare.ShareControllerOptions = {};
          controller.show(abilityContext, options)
            .then(() => {
              result.success(null);
            })
            .catch((err: BusinessError) => {
              result.error('SHARE_FAILED', `${err.code}: ${err.message}`, null);
            });
        } else if (isPickerMethod(call.method)) {
          handlePickerCall(abilityContext, call, result);
        } else {
          result.notImplemented();
        }
      },
    });

    // 华为账号（Account Kit v4 / API 11）：
    // AuthorizationWithHuaweiIDRequest -> executeRequest -> authorizationCode，
    // authorizationCode 交给服务端换取 token / userinfo。
    const huaweiChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(),
      CHANNEL_HUAWEI,
    );
    huaweiChannel.setMethodCallHandler({
      onMethodCall(call: MethodCall, result: MethodResult): void {
        if (call.method === 'login') {
          if (OFFLINE_ONLY) {
            result.error('OFFLINE_ONLY', '独立离线版不提供账号登录', null);
            return;
          }
          try {
            const provider = new authentication.HuaweiIDProvider();
            const request: authentication.AuthorizationWithHuaweiIDRequest =
              provider.createAuthorizationWithHuaweiIDRequest();
            request.scopes = ['openid'];
            request.permissions = [];

            const controller =
              new authentication.AuthenticationController(abilityContext);
            controller.executeRequest(request)
              .then((response: authentication.AuthenticationResponse) => {
                const authResponse =
                  response as authentication.AuthorizationWithHuaweiIDResponse;
                const code: string =
                  authResponse.data?.authorizationCode ?? '';
                if (code.length > 0) {
                  result.success(code);
                } else {
                  result.error('HUAWEI_LOGIN_EMPTY', '未获取到授权码', null);
                }
              })
              .catch((err: BusinessError) => {
                result.error('HUAWEI_LOGIN_FAILED', `${err.code}: ${err.message}`, null);
              });
          } catch (e) {
            const err = e as BusinessError;
            result.error('HUAWEI_LOGIN_ERROR', `${err.code}: ${err.message}`, null);
          }
        } else {
          result.notImplemented();
        }
      },
    });
  }
}
