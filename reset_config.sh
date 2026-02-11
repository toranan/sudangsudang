
#!/bin/bash

# 경로 수정: 오늘얼마?/오늘얼마?/오늘얼마?.xcodeproj/project.pbxproj
PROJECT_FILE="/Users/anseung-won/Desktop/오늘얼마?/오늘얼마?/오늘얼마?.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "❌ 파일을 찾을 수 없습니다: $PROJECT_FILE"
    exit 1
fi

# 백업 생성
cp "$PROJECT_FILE" "$PROJECT_FILE.bak"

# 1. CODE_SIGN_STYLE = Manual 삭제 (-> Automatic으로 돌아감)
sed -i '' '/CODE_SIGN_STYLE = Manual;/d' "$PROJECT_FILE"

# 2. PROVISIONING_PROFILE_SPECIFIER 삭제
sed -i '' '/PROVISIONING_PROFILE_SPECIFIER/d' "$PROJECT_FILE"

# 3. CODE_SIGN_IDENTITY 강제 설정 삭제
sed -i '' '/"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = "Apple Distribution";/d' "$PROJECT_FILE"
sed -i '' '/CODE_SIGN_IDENTITY = "Apple Distribution";/d' "$PROJECT_FILE"
sed -i '' '/CODE_SIGN_IDENTITY = "Apple Development";/d' "$PROJECT_FILE"

echo "✅ 프로젝트 설정이 초기화되었습니다. Xcode를 재실행해주세요."
