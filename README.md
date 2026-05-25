# 정리시간

iOS와 macOS에서 같이 쓰는 5분 단위 시간표 앱입니다.

## 첫 버전 범위

- 현재 시각의 5분 블록 확인
- 오늘 남은 자유시간 계산
- 요일별 일정 블록 보기
- 날짜별 누락 정보 확인 및 완료 체크
- iPhone, iPad, Mac용 SwiftUI 공용 코드

## 열기

`JeongriTime.xcodeproj`를 Xcode에서 열고 다음 스킴 중 하나를 실행합니다.

- `JeongriTime-macOS`
- `JeongriTime-iOS`

## 검증

```sh
swift test
xcodebuild -project JeongriTime.xcodeproj -scheme JeongriTime-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project JeongriTime.xcodeproj -scheme JeongriTime-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
