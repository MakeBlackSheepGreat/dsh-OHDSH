export {
  IHoldingAwarenessManager,
  NGFHoldingAwarenessConfidence,
  NGFHoldingAwarenessListener,
  NGFHoldingAwarenessSide,
  NGFHoldingAwarenessSnapshot,
  NGFHoldingAwarenessSource,
  NGFHoldingUiAnchor
} from './contracts/IHoldingAwarenessManager';

export {
  IDeviceAdaptationManager,
  NGFBreakpoint,
  NGFDeviceChangeListener,
  NGFDeviceInfo,
  NGFDeviceType,
  NGFFoldStatus,
  NGFScreenOrientation,
  NGFRuntimeStatus,
  NGFAppThreadInfo
} from './contracts/IDeviceAdaptationManager';

// [HDSH] UIDesignKit 不兼容，IVisualEffectsManager 导出已整体裁剪


export { IAdaptiveLayout, NGFBreakpointLayoutConfig } from './contracts/IAdaptiveLayout';
export {
  IDeviceCapabilityDetector,
  NGFCapabilityType,
  NGFCapabilityResult
} from './contracts/IDeviceCapabilityDetector';

export { ngfHoldingAwarenessFacade } from './facades/HoldingAwarenessFacade';
export { ngfDeviceAdaptationFacade } from './facades/DeviceAdaptationFacade';
// [HDSH] UIDesignKit 不兼容，已裁剪
// export { ngfVisualEffectsFacade } from './facades/VisualEffectsFacade';
export { ngfAdaptiveLayoutFacade } from './facades/AdaptiveLayoutFacade';
export { DeviceCapabilityDetectorFacade, ngfDeviceCapabilityDetectorFacade } from './facades/DeviceCapabilityDetectorFacade';
export { ngfDeviceAwarenessIntegrationFacade } from './facades/NGFDeviceAwarenessIntegrationFacade';
