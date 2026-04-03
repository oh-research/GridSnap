# GridSnap

<p align="center">
  <img src="Resources/gridsnap_icon.svg" width="128" alt="GridSnap icon">
</p>

> Shift + 드래그로 윈도우를 커스텀 그리드에 스냅하는 macOS 유틸리티

macOS에 내장된 윈도우 스냅은 화면 절반 정도만 지원합니다. GridSnap은 사용자가 정의한 그리드(2x2, 3x3, 4x3 등)에 맞춰 창을 자유롭게 배치합니다.

## 특징

- **Shift + 제목줄 드래그** — 그리드 오버레이 표시, 놓으면 셀에 스냅
- **Cmd 추가** — 여러 셀에 걸친 직사각형 영역으로 스냅
- **다중 모니터 지원** — 각 화면에 독립 그리드 표시
- **메뉴바 앱** — Dock 아이콘 없이 메뉴바에서만 동작
- **그리드 프리셋** — 2x2, 2x3, 2x4 + 행/열 자유 설정 (1~10)
- **다크/라이트 모드** 자동 대응
- **로그인 시 자동 실행** 지원
- 외부 의존성 없음 (순수 Swift + AppKit + SwiftUI)

## 설치

### Homebrew (추천)

```bash
brew tap oh-research/tap
brew install --cask gridsnap
```

### 수동 설치

1. [Releases](https://github.com/oh-research/GridSnap/releases)에서 `.dmg` 다운로드
2. `GridSnap.app`을 `/Applications`로 드래그
3. 최초 실행 전 Gatekeeper 우회:
   ```bash
   xattr -cr /Applications/GridSnap.app
   ```
4. 앱을 실행하면 온보딩 화면이 나타납니다

## 사용법

### 단일 셀 스냅

1. 창 제목줄을 드래그하면서 **Shift**를 누르세요
2. 화면에 그리드 오버레이가 나타나고 커서 위치의 셀이 하이라이트됩니다
3. 마우스를 놓으면 창이 해당 셀 크기/위치로 스냅됩니다

### 다중 셀 스냅

1. Shift + 드래그 중 **Cmd**를 추가로 누르세요
2. Cmd를 누른 시점의 셀이 앵커가 되고, 커서 이동에 따라 직사각형 영역이 하이라이트됩니다
3. 마우스를 놓으면 직사각형 영역 전체 크기로 스냅됩니다

## 권한

GridSnap은 두 가지 macOS 권한이 필요합니다:

- **손쉬운 사용(Accessibility)** — 창 이동/크기 조절에 필요
- **입력 모니터링(Input Monitoring)** — Shift + 드래그 제스처 감지에 필요

첫 실행 시 온보딩 화면에서 권한 설정을 안내합니다.

## 설정

메뉴바 아이콘 > **설정**에서 변경할 수 있습니다:

- **행/열 수** (1~10)
- **프리셋** — 2x2, 2x3, 2x4
- **로그인 시 자동 실행**

## 소스에서 빌드

macOS 15+ 및 Swift 6이 필요합니다.

```bash
git clone https://github.com/oh-research/GridSnap.git
cd GridSnap
swift build
swift run
```

## 요구 사항

- macOS 15.0 (Sequoia) 이상

## 삭제

### Homebrew

```bash
brew uninstall --cask gridsnap
```

### 수동 삭제

```bash
rm -rf /Applications/GridSnap.app
```

## 기술 스택

- **Swift 6 + AppKit** — 이벤트 감지, 오버레이, 창 조작
- **SwiftUI** — 설정 UI, 온보딩
- **CGEventTap** (passive) — 마우스/modifier 이벤트 수신
- **AXUIElement** — 커서 아래 창 획득 및 크기/위치 변경
- **SPM** — 패키지 관리

## 라이선스

MIT License
