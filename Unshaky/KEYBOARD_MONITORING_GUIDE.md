# 키보드 모니터링 가이드

## 개요

Unshaky는 이제 IOKit을 사용하여 내장/외장 키보드를 정확히 구분하고, 설정에 따라 지능적으로 모니터링을 활성화/비활성화합니다.

## 동작 방식

### 1. 자동 키보드 감지

앱이 시작되면 자동으로:
- 연결된 모든 키보드를 IOKit으로 스캔
- 각 키보드가 내장인지 외장인지 판별
- 설정에 따라 모니터링 필요 여부 결정

### 2. 실시간 업데이트

키보드를 연결하거나 해제하면:
- 자동으로 키보드 목록 갱신
- 모니터링 상태 재평가
- 필요시 이벤트 탭 활성화/비활성화

### 3. 지능형 리소스 관리

모니터링이 필요 없는 경우 이벤트 탭을 완전히 제거하여:
- CPU 사용량 감소
- 배터리 수명 향상
- 시스템 부하 최소화

## 설정 시나리오

### 시나리오 1: 내장 키보드만 문제가 있는 경우 (가장 일반적)

**설정:**
- ✅ Ignore External Keyboard (외장 키보드 무시)
- ❌ Ignore Internal Keyboard (내장 키보드 무시 안 함)

**동작:**
- 내장 키보드만 사용 시: 모니터링 활성화 ✅
- 외장 키보드만 사용 시: 모니터링 비활성화 ⚡ (리소스 절약)
- 둘 다 사용 시: 내장 키보드만 필터링, 외장은 통과

**사용 예:**
```
MacBook 내장 키보드가 고장나서 이중 입력 발생
→ 외장 키보드 연결하면 자동으로 모니터링 중단
→ 외장 키보드 해제하면 자동으로 모니터링 재개
```

### 시나리오 2: 외장 키보드만 문제가 있는 경우 (드문 경우)

**설정:**
- ❌ Ignore External Keyboard (외장 키보드 무시 안 함)
- ✅ Ignore Internal Keyboard (내장 키보드 무시)

**동작:**
- 내장 키보드만 사용 시: 모니터링 비활성화 ⚡
- 외장 키보드만 사용 시: 모니터링 활성화 ✅
- 둘 다 사용 시: 외장 키보드만 필터링, 내장은 통과

### 시나리오 3: 모든 키보드 모니터링 (기본값)

**설정:**
- ❌ Ignore External Keyboard
- ❌ Ignore Internal Keyboard

**동작:**
- 항상 모니터링 활성화 ✅
- 모든 키보드에 필터링 적용

### 시나리오 4: 모니터링 완전 비활성화

**설정:**
- ✅ Ignore External Keyboard
- ✅ Ignore Internal Keyboard

**동작:**
- 항상 모니터링 비활성화 ⚡
- 이벤트 탭 제거
- 최소 리소스 사용

## 로그 확인

Console.app 또는 Xcode에서 로그를 확인할 수 있습니다:

```bash
# Console.app에서 필터링
Process: Unshaky
Subsystem: [Unshaky]

# 또는 터미널에서
log stream --predicate 'process == "Unshaky"' --level debug
```

### 주요 로그 메시지

**키보드 감지:**
```
[Unshaky] Detected 2 keyboard(s)
  - Apple Internal Keyboard / Trackpad (Built-in: YES, Transport: ADB)
  - Keychron K2 (Built-in: NO, Transport: Bluetooth)
```

**모니터링 활성화:**
```
[Unshaky] Monitoring enabled. Built-in: YES, External: YES, Ignore Internal: NO, Ignore External: NO
[Unshaky] Enabling event tap - keyboards need monitoring
```

**모니터링 비활성화:**
```
[Unshaky] Only external keyboard detected and it's ignored. Monitoring disabled.
[Unshaky] Disabling event tap - no keyboards to monitor
```

**키보드 연결/해제:**
```
[Unshaky] Keyboard connected
[Unshaky] Keyboard connection changed, updating monitoring state
```

## 디버그 모드

디버그 창을 열면 연결된 키보드 정보를 확인할 수 있습니다:

1. 메뉴바에서 Unshaky 아이콘 클릭
2. "Debug" 선택
3. 자동으로 키보드 목록 표시:

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

## 문제 해결

### 키보드가 감지되지 않는 경우

1. 앱 재시작
2. 키보드 재연결
3. 디버그 창에서 키보드 목록 확인

### 모니터링이 작동하지 않는 경우

1. 설정 확인:
   - 둘 다 "Ignore" 설정되어 있지 않은지 확인
   - 해당 키보드 타입이 무시 설정되어 있지 않은지 확인

2. 권한 확인:
   - System Preferences → Security & Privacy → Privacy
   - Accessibility: Unshaky 체크
   - Input Monitoring: Unshaky 체크

3. 로그 확인:
   - Console.app에서 "[Unshaky]" 필터링
   - 모니터링 상태 메시지 확인

### 외장 키보드가 내장으로 인식되는 경우

일부 특수한 키보드는 잘못 인식될 수 있습니다:
- Apple Magic Keyboard (일부 모델)
- 특정 USB-C 허브를 통한 키보드
- 일부 KVM 스위치를 통한 키보드

이 경우 "Ignore" 설정을 조정하여 우회할 수 있습니다.

## 성능 영향

### 이전 버전:
- 항상 모든 키 입력 모니터링
- CPU 사용량: ~1-2% (유휴 시)
- 배터리 영향: 중간

### 현재 버전:
- 필요시에만 모니터링
- CPU 사용량: ~0% (모니터링 비활성화 시)
- 배터리 영향: 최소

### 권장 설정 (배터리 최적화):

외장 키보드 사용 시:
```
✅ Ignore External Keyboard
❌ Ignore Internal Keyboard
```

이렇게 하면 외장 키보드만 사용할 때 자동으로 모니터링이 중단되어 배터리를 절약할 수 있습니다.
