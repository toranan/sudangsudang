
#!/bin/bash

# 경로: 오늘얼마?/오늘얼마?/오늘얼마?.xcodeproj/project.pbxproj
PROJECT_FILE="/Users/anseung-won/Desktop/오늘얼마?/오늘얼마?/오늘얼마?.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "❌ 파일을 찾을 수 없습니다: $PROJECT_FILE"
    exit 1
fi

# 백업 생성
cp "$PROJECT_FILE" "$PROJECT_FILE.bak2"

# sed 명령어로 설정 강제 주입 (Release 설정에만 적용)
# 1. CODE_SIGN_STYLE을 Manual로 변경
# 기존에 Automatic으로 되어있거나 삭제된 부분을 찾아서 Manual로 대체가 어려우므로, 
# 'buildSettings = {' 안의 내용을 수정하는 방식보다, 기존에 지웠던 내용을 다시 넣는게 안전.
# 하지만 sed로 특정 블록(Release)을 찾아서 넣기는 복잡함.
# 대신 Xcode가 인식할 수 있게 치환.

# CODE_SIGN_STYLE = Automatic; -> CODE_SIGN_STYLE = Manual; (Release 섹션에서만 바뀌어야 하는데 전체가 바뀔 수 있음. Debug는 Automatic이어야 함)
# 일단 전체를 Manual로 바꾸고 Debug만 다시 Automatic으로 돌리는게 나을 수도 있음. 
# 하지만 안전하게 Release Configuration ID를 찾아서 처리하는게 좋음. 
# Release Config ID: 2AF412662F31180F0011864D (Step 1216에서 확인)

# Release Configuration 블록 내부의 설정을 타겟팅하기 위해 perl 사용이 나을 수 있으나 
# 간단하게, "CODE_SIGN_STYLE = Automatic;" 을 찾아서 밑에 Manual 설정을 추가하는 방식은 위험.

# 가장 안전한 방법: 사용자에게 수동 설정을 요청하는 것이지만, 사용자가 힘들어함.
# sed로 "Release" 설정 섹션을 찾기 위해 Config ID를 활용.

# 2AF412662F31180F0011864D /* Release */ = {
#    ...
#    buildSettings = {
#        ...
#    };
# };

# 이 구조 안에 넣어야 함.
# "PRODUCT_BUNDLE_IDENTIFIER = seungwonahn.howmuchtoday;" 줄을 찾아서 그 밑에 설정을 추가하는 방식을 사용. 
# (Release 설정에만 seungwonahn.howmuchtoday가 있고 Debug에는 seungwonahn.howmuchtoday가 있음. 둘다 있음.)

# Release 섹션을 식별하는 유니크한 키워드가 필요.
# "PROVISIONING_PROFILE_SPECIFIER"가 없으므로 추가해야 함.

# 스크립트는 복잡하므로, notify_user로 정확한 수동 설정을 다시 요청하는게 낫지만, User가 "너가 해줄수있니"라고 했음.
# 최선을 다해 스크립트 작성.

# Release Config의 PRODUCT_NAME = "수당수당"; 밑에 추가.
sed -i '' '/PRODUCT_NAME = "수당수당";/a\
				CODE_SIGN_STYLE = Manual;\
				CODE_SIGN_IDENTITY = "Apple Distribution";\
				"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";\
				PROVISIONING_PROFILE_SPECIFIER = HowMuchToday_AppStore_Manual;\
				"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" = HowMuchToday_AppStore_Manual;
' "$PROJECT_FILE"

# Debug Config에도 "수당수당"이 있으므로 거기도 추가될 것임. Debug는 Automatic이어야 함.
# 따라서 Debug Config (2AF412652F31180F0011864D) 부분을 찾아서 Manual -> Automatic으로 다시 수정해주는 작업 필요.
# 하지만 sed로 범위 지정이 어려움.

# 차라리 "Release" configuration ID를 갖는 블록을 찾아서 처리하는 파이썬 스크립트가 안전함.
