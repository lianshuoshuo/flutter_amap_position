import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { FlutterAbility, FlutterEngine, MethodChannel } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  private permissions?: MethodChannel;

  configureFlutterEngine(engine: FlutterEngine): void {
    super.configureFlutterEngine(engine);
    GeneratedPluginRegistrant.registerWith(engine);
    this.permissions = new MethodChannel(engine.getDartExecutor(), 'dev.hscw.flutter_amap_position/example_permissions');
    this.permissions.setMethodCallHandler({
      onMethodCall: (call, result) => {
        if (call.method !== 'request') {
          result.notImplemented();
          return;
        }
        const names: Array<Permissions> = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
        abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, names)
          .then((reply) => result.success(reply.authResults.some((value) => value === 0)))
          .catch(() => result.error('permission_request_failed', null, null));
      }
    });
  }

  cleanUpFlutterEngine(engine: FlutterEngine): void {
    this.permissions?.setMethodCallHandler(null);
    this.permissions = undefined;
    super.cleanUpFlutterEngine(engine);
  }
}
