import common from '@ohos.app.ability.common';
import ApplicationStateChangeCallback from '@ohos.app.ability.ApplicationStateChangeCallback';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import geoLocationManager from '@ohos.geoLocationManager';
import { BusinessError } from '@ohos.base';
import {
  AMapPrivacyAgreeStatus,
  AMapPrivacyInfoStatus,
  AMapPrivacyShowStatus,
} from '@amap/amap_lbs_common';
import {
  AMapLocation,
  AMapLocationErrorCode,
  AMapLocationManagerImpl,
  AMapLocationOption,
  AMapLocationType,
  IAMapLocationListener,
} from '@amap/amap_lbs_location';
import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

class Request {
  manager?: AMapLocationManagerImpl;
  timer?: number;

  readonly id: string | null;
  readonly result: MethodResult | null;
  readonly type: AMapLocationType;

  constructor(id: string | null, result: MethodResult | null, type: AMapLocationType) {
    this.id = id;
    this.result = result;
    this.type = type;
  }
}

export default class FlutterAmapPositionPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel;
  private app?: common.ApplicationContext;
  private context?: common.UIAbilityContext;
  private foreground: boolean = false;
  private initialized: boolean = false;
  private privacyDeclined: boolean = false;
  private clientId?: string;
  private active?: Request;
  private readonly lifecycle: ApplicationStateChangeCallback = {
    onApplicationForeground: () => {
      this.foreground = this.context !== undefined;
    },
    onApplicationBackground: () => {
      this.leaveForeground();
    },
  };

  getUniqueClassName(): string {
    return 'FlutterAmapPositionPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.app = binding.getApplicationContext().getApplicationContext();
    this.app.on('applicationStateChange', this.lifecycle);
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'dev.hscw.flutter_amap_position/location');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    const request = this.active;
    if (request) {
      this.fail(request, 'cancelled');
    }
    this.app?.off('applicationStateChange', this.lifecycle);
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.app = undefined;
    this.context = undefined;
    this.foreground = false;
    this.initialized = false;
    this.privacyDeclined = false;
    this.clientId = undefined;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
    this.foreground = true;
  }

  onDetachedFromAbility(): void {
    this.context = undefined;
    this.leaveForeground();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'initialize':
        this.initialize(call, result);
        break;
      case 'getCurrentPosition': {
        const timeoutMs = call.argument('timeoutMs') as number;
        if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 0x7fffffff) {
          result.error('invalid_argument', null, null);
          return;
        }
        this.start(new Request(null, result, AMapLocationType.Single), timeoutMs, result);
        break;
      }
      case 'startUpdates': {
        const id = call.argument('id') as string;
        if (typeof id !== 'string' || id.length === 0) {
          result.error('invalid_argument', null, null);
          return;
        }
        this.start(new Request(id, null, AMapLocationType.Updating), undefined, result);
        break;
      }
      case 'stopUpdates': {
        const request = this.active;
        if (request && request.id !== null && request.id === call.argument('id')) {
          const error = this.release(request);
          if (error) {
            result.error('sdk_failure', null, this.details(error.code));
            return;
          }
        }
        result.success(null);
        break;
      }
      default:
        result.notImplemented();
    }
  }

  private initialize(call: MethodCall, result: MethodResult): void {
    const request = this.active;
    if (call.argument('privacyAgreed') !== true) {
      this.initialized = false;
      this.privacyDeclined = true;
      if (request) {
        this.fail(request, 'privacy_not_agreed');
      }
      result.error('privacy_not_agreed', null, null);
      return;
    }
    const key = call.argument('apiKey') as string;
    const caller = call.argument('clientId') as string;
    if (typeof key !== 'string' || key.trim().length === 0 || typeof caller !== 'string' || caller.length === 0) {
      result.error('invalid_argument', null, null);
      return;
    }
    if (request && this.clientId !== caller) {
      this.fail(request, 'cancelled');
    }
    if (this.active) {
      result.error('busy', null, null);
      return;
    }
    if (!this.app) {
      result.error('not_initialized', null, null);
      return;
    }
    this.initialized = false;
    this.privacyDeclined = false;
    try {
      AMapLocationManagerImpl.updatePrivacyShow(AMapPrivacyShowStatus.DidShow,
        AMapPrivacyInfoStatus.DidContain, this.app);
      AMapLocationManagerImpl.updatePrivacyAgree(AMapPrivacyAgreeStatus.DidAgree, this.app);
      AMapLocationManagerImpl.setApiKey(key.trim());
      this.clientId = caller;
      this.initialized = true;
      result.success(null);
    } catch (error) {
      result.error('sdk_failure', null, this.details((error as BusinessError).code));
    }
  }

  private start(request: Request, timeoutMs: number | undefined, result: MethodResult): void {
    if (this.privacyDeclined) {
      result.error('privacy_not_agreed', null, null);
      return;
    }
    if (!this.initialized) {
      result.error('not_initialized', null, null);
      return;
    }
    if (this.active) {
      result.error('busy', null, null);
      return;
    }
    const context = this.context;
    if (!this.foreground || !context) {
      result.error('not_in_foreground', null, null);
      return;
    }
    try {
      if (!geoLocationManager.isLocationEnabled()) {
        result.error('location_services_disabled', null, null);
        return;
      }
      const permissions = abilityAccessCtrl.createAtManager();
      const token = context.applicationInfo.accessTokenId;
      if (permissions.checkAccessTokenSync(token, 'ohos.permission.APPROXIMATELY_LOCATION') !==
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED &&
        permissions.checkAccessTokenSync(token, 'ohos.permission.LOCATION') !==
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        result.error('permission_denied', null, null);
        return;
      }

      const manager = new AMapLocationManagerImpl(context);
      request.manager = manager;
      this.active = request;
      const options: AMapLocationOption = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        scenario: geoLocationManager.LocationRequestScenario.UNSET,
        timeInterval: 2,
        locatingWithReGeocode: false,
        allowsBackgroundLocationUpdates: false,
        isOffset: true,
      };
      if (timeoutMs !== undefined) {
        options.singleLocationTimeout = Math.max(1000, Math.min(0x7fffffff, timeoutMs + 1000));
        request.timer = setTimeout(() => this.fail(request, 'timeout'), timeoutMs);
      }
      manager.setLocationOption(request.type, options);
      const listener: IAMapLocationListener = {
        onLocationChanged: (fix) => {
          // Defer callbacks until the start command has been acknowledged.
          Promise.resolve().then(() => this.receive(request, fix));
        },
        onLocationError: (error) => {
          Promise.resolve().then(() => this.fail(request, this.sdkError(error.errorCode), error.errorCode));
        },
      };
      manager.setLocationListener(request.type, listener);
      if (timeoutMs === undefined) {
        manager.startUpdatingLocation();
        result.success(null);
      } else {
        manager.requestSingleLocation();
      }
    } catch (error) {
      if (this.active === request) {
        this.release(request);
      }
      const code = (error as BusinessError).code;
      result.error(this.sdkError(code), null, this.details(code));
    }
  }

  private receive(request: Request, fix: AMapLocation): void {
    if (this.active !== request) {
      return;
    }
    const data = new Map<string, Object>();
    data.set('latitude', fix.latitude);
    data.set('longitude', fix.longitude);
    data.set('horizontalAccuracy', fix.accuracy);
    data.set('timestamp', fix.timeStamp);
    data.set('coordinateSystem', fix.coordType ?? 'UNKNOWN');

    if (request.result) {
      const error = this.release(request);
      if (error) {
        request.result.error('sdk_failure', null, this.details(error.code));
      } else {
        request.result.success(data);
      }
    } else if (request.id !== null) {
      const event = new Map<string, Object>();
      event.set('id', request.id);
      event.set('fix', data);
      this.channel?.invokeMethod('position', event);
    }
  }

  private sdkError(code?: number): string {
    switch (code) {
      case AMapLocationErrorCode.ERROR_CHECK_PRIVACY:
        return 'privacy_not_agreed';
      case 201:
      case AMapLocationErrorCode.ERROR_CHECK_PERMINSSION:
        return 'permission_denied';
      case AMapLocationErrorCode.ERROR_LOCATION_SERVICE_CLOSE:
        return 'location_services_disabled';
      case 801:
        return 'unsupported_platform';
      default:
        return 'sdk_failure';
    }
  }

  private leaveForeground(): void {
    this.foreground = false;
    if (this.active) {
      this.fail(this.active, 'not_in_foreground');
    }
  }

  private details(nativeCode?: number): Map<string, Object> | null {
    if (typeof nativeCode !== 'number') {
      return null;
    }
    const value = new Map<string, Object>();
    value.set('nativeCode', nativeCode);
    value.set('nativeDomain', 'AMapLocation');
    return value;
  }

  private fail(request: Request, code: string, nativeCode?: number): void {
    if (this.active !== request) {
      return;
    }
    this.release(request);
    const details = this.details(nativeCode);
    if (request.result) {
      request.result.error(code, null, details);
    } else if (request.id !== null) {
      const event = new Map<string, Object>();
      event.set('id', request.id);
      event.set('code', code);
      if (details) {
        event.set('details', details);
      }
      this.channel?.invokeMethod('positionError', event);
    }
  }

  private release(request: Request): BusinessError | undefined {
    this.active = undefined;
    if (request.timer !== undefined) {
      clearTimeout(request.timer);
    }
    const manager = request.manager;
    request.manager = undefined;
    if (!manager) {
      return;
    }
    let failure: BusinessError | undefined;
    try {
      manager.unRegisterLocationListener(request.type);
    } catch (error) {
      failure = error as BusinessError;
    }
    try {
      if (request.type === AMapLocationType.Updating) {
        manager.stopUpdatingLocation();
      }
    } catch (error) {
      failure = failure ?? error as BusinessError;
    }
    try {
      manager.onDestroy();
    } catch (error) {
      failure = failure ?? error as BusinessError;
    }
    return failure;
  }
}
