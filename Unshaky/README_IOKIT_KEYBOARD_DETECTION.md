# IOKit 기반 키보드 감지 기능

## 개요

이 업데이트는 IOKit을 활용하여 내장 키보드와 외장 키보드를 더 정확하게 구분합니다.

## 주요 변경사항

### 1. IOKit 기반 키보드 감지 (`PerformanceOptimizations.h/m`)

**새로운 기능:**
- `KeyboardTypeDetector` 클래스에 IOKit 기반 감지 메서드 추가
- HID (Human Interface Device) Manager를 사용한 실시간 키보드 감지
- 연결된 모든 키보드의 상세 정보 수집
- **키보드 연결/해제 자동 감지 및 모니터링 상태 자동 조정**

**감지 기준:**
- **내장 키보드 판별:**
  - Apple Vendor ID (0x05ac)
  - Transport 타입: "ADB" 또는 비어있음
  - 제품명에 "Internal" 또는 "Built-in" 포함
  
- **수집 정보:**
  - Vendor ID / Product ID
  - Transport 방식 (USB, Bluetooth, ADB 등)
  - 제품명
  - Location ID
  - 내장/외장 여부

**지능형 모니터링:**
- 연결된 키보드 타입과 설정에 따라 이벤트 탭을 자동으로 활성화/비활성화
- 불필요한 시스템 리소스 사용 방지
- 예시:
  - 내장 키보드만 있고 "Ignore Internal Keyboard" 활성화 → 모니터링 비활성화
  - 외장 키보드만 있고 "Ignore External Keyboard" 활성화 → 모니터링 비활성화
  - 둘 다 무시 설정 → 모니터링 비활성화

### 2. 향상된 필터링 및 지능형 모니터링 (`ShakyPressPreventer.m`)

**IOKit 기반 정확한 감지:**
```objective-c
// 이전: 단순 타입 범위 체크
BOOL isInternalKeyboard = [KeyboardTypeDetector isInternalKeyboard:keyboardType];

// 이후: IOKit 기반 정확한 감지
BOOL isInternalKeyboard = [[KeyboardTypeDetector sharedInstance] isInternalKeyboardWithIOKit:keyboardType];
```

**자동 모니터링 상태 관리:**
- `updateMonitoringState` 메서드로 현재 연결된 키보드와 설정을 확인
- 모니터링이 필요 없으면 이벤트 탭을 자동으로 제거하여 시스템 리소스 절약
- 키보드 연결/해제 시 자동으로 모니터링 상태 재평가

**동작 로직:**
```objective-c
- (void)updateMonitoringState {
    // 키보드 목록 새로고침
    [[KeyboardTypeDetector sharedInstance] refreshKeyboardList];
    
    // 모니터링 필요 여부 확인
    BOOL shouldMonitor = [[KeyboardTypeDetector sharedInstance] 
                          shouldMonitorWithIgnoreInternal:ignoreInternalKeyboard 
                          ignoreExternal:ignoreExternalKeyboard];
    
    // 필요에 따라 이벤트 탭 활성화/비활성화
    if (!shouldMonitor && [self eventTapEnabled]) {
        [self removeEventTap];  // 리소스 절약
    } else if (shouldMonitor && ![self eventTapEnabled]) {
        [self setupEventTap];   // 모니터링 시작
    }
}
```

### 3. 디버그 기능 추가 (`DebugViewController.h/m`)

**새로운 메서드:**
- `showConnectedKeyboards`: 연결된 모든 키보드 정보를 디버그 뷰에 표시

**표시 정보:**
```
========== Connected Keyboards ==========

📱 Apple Internal Keyboard / Trackpad
   Type: Built-in (Internal)
   Transport: ADB
   Vendor ID: 0x05AC
   Product ID: 0x027E

📱 Keychron K2
   Type: External
   Transport: Bluetooth
   Vendor ID: 0x3434
   Product ID: 0x0232

=========================================
```

## 사용 방법

### 1. 기본 설정 (기존과 동일)

환경설정에서 다음 옵션을 사용할 수 있습니다:
- **Ignore External Keyboard**: 외장 키보드 입력은 필터링하지 않음
- **Ignore Internal Keyboard**: 내장 키보드 입력은 필터링하지 않음

### 2. 디버그 모드에서 키보드 확인

디버그 창을 열고 연결된 키보드 정보를 확인하려면:

```objective-c
// AppDelegate 또는 적절한 위치에서
DebugViewController *debugVC = ...; // 디버그 뷰 컨트롤러 참조
[debugVC showConnectedKeyboards];
```

### 3. 프로그래밍 방식으로 키보드 정보 가져오기

```objective-c
#import "PerformanceOptimizations.h"

// 모든 연결된 키보드 정보 가져오기
NSArray<NSDictionary *> *keyboards = [[KeyboardTypeDetector sharedInstance] getAllConnectedKeyboards];

for (NSDictionary *keyboard in keyboards) {
    NSString *name = keyboard[@"productName"];
    BOOL isBuiltIn = [keyboard[@"isBuiltIn"] boolValue];
    NSLog(@"%@ - Built-in: %@", name, isBuiltIn ? @"YES" : @"NO");
}

// 키보드 목록 새로고침
[[KeyboardTypeDetector sharedInstance] refreshKeyboardList];
```

## 기술적 세부사항

### IOKit HID Manager 설정

```objective-c
IOHIDManagerRef hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);

// 키보드 장치만 필터링
NSDictionary *matchingDict = @{
    @(kIOHIDDeviceUsagePageKey): @(kHIDPage_GenericDesktop),
    @(kIOHIDDeviceUsageKey): @(kHIDUsage_GD_Keyboard)
};

IOHIDManagerSetDeviceMatching(hidManager, (__bridge CFDictionaryRef)matchingDict);
```

### 내장 키보드 판별 로직

1. **Vendor ID 확인**: Apple (0x05ac)인지 확인
2. **Transport 확인**: "ADB" 또는 비어있으면 내장 가능성 높음
3. **제품명 확인**: "Internal" 또는 "Built-in" 포함 여부
4. **CGEvent keyboardType 확인**: 58-70 범위는 일반적으로 내장 키보드

### 성능 최적화

- 키보드 정보는 캐시되어 반복적인 IOKit 호출 방지
- 백그라운드 큐에서 키보드 목록 갱신
- 동기화된 접근으로 스레드 안전성 보장

## 호환성

- **macOS 버전**: 10.11 (El Capitan) 이상
- **아키텍처**: Intel 및 Apple Silicon (M1/M2/M3) 모두 지원
- **키보드 타입**: 
  - MacBook 내장 키보드 (모든 세대)
  - USB 외장 키보드
  - Bluetooth 키보드
  - Magic Keyboard

## 알려진 제한사항

1. **CGEvent keyboardType 매핑**: CGEvent의 `keyboardType` 필드와 IOKit 장치를 직접 매핑하는 것은 불가능합니다. 현재 구현은 감지된 키보드 정보와 타입 범위를 조합하여 판별합니다.

2. **동적 연결/해제**: 키보드가 연결되거나 해제될 때 자동으로 감지되지만, 캐시 갱신을 위해 `refreshKeyboardList()`를 호출하는 것이 좋습니다.

3. **일부 서드파티 키보드**: 특이한 Vendor ID나 Transport를 사용하는 일부 키보드는 정확히 분류되지 않을 수 있습니다.

## 시스템 리소스 최적화

### 이전 동작:
- 모든 키 입력을 항상 모니터링
- 설정과 관계없이 이벤트 탭 항상 활성화
- 불필요한 CPU 및 배터리 사용

### 현재 동작:
- **지능형 모니터링**: 연결된 키보드와 설정에 따라 자동으로 이벤트 탭 활성화/비활성화
- **자동 감지**: 키보드 연결/해제 시 자동으로 모니터링 상태 재평가
- **리소스 절약**: 모니터링이 필요 없을 때는 이벤트 탭을 완전히 제거

### 모니터링 비활성화 조건:
1. **둘 다 무시**: `ignoreInternalKeyboard` && `ignoreExternalKeyboard` 모두 활성화
2. **내장만 있고 무시**: 내장 키보드만 연결되어 있고 `ignoreInternalKeyboard` 활성화
3. **외장만 있고 무시**: 외장 키보드만 연결되어 있고 `ignoreExternalKeyboard` 활성화

### 로그 예시:
```
[Unshaky] Keyboard connected
[Unshaky] Detected 2 keyboard(s)
  - Apple Internal Keyboard / Trackpad (Built-in: YES, Transport: ADB)
  - Keychron K2 (Built-in: NO, Transport: Bluetooth)
[Unshaky] Monitoring enabled. Built-in: YES, External: YES, Ignore Internal: NO, Ignore External: NO

[Unshaky] Keyboard disconnected
[Unshaky] Detected 1 keyboard(s)
  - Apple Internal Keyboard / Trackpad (Built-in: YES, Transport: ADB)
[Unshaky] Only internal keyboard detected and it's ignored. Monitoring disabled.
[Unshaky] Disabling event tap - no keyboards to monitor
```

## 향후 개선 사항

- [x] 키보드 연결/해제 이벤트 자동 감지 및 캐시 갱신 ✅
- [x] 지능형 모니터링 상태 관리로 시스템 리소스 최적화 ✅
- [ ] UI에 연결된 키보드 목록 표시
- [ ] 키보드별 개별 설정 (특정 외장 키보드만 필터링 등)
- [ ] CGEvent keyboardType과 IOKit 장치의 정확한 매핑 방법 연구

## 테스트 방법

1. 앱 실행 후 디버그 모드 활성화
2. `showConnectedKeyboards` 호출하여 감지된 키보드 확인
3. 외장 키보드 연결/해제하며 감지 확인
4. "Ignore External Keyboard" 옵션 활성화 후 외장 키보드로 타이핑 - 필터링 안 됨
5. "Ignore Internal Keyboard" 옵션 활성화 후 내장 키보드로 타이핑 - 필터링 안 됨

## 문의 및 기여

이 기능에 대한 피드백이나 개선 제안은 GitHub Issues를 통해 제출해주세요.
