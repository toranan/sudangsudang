
import sys
import re

project_path = "/Users/anseung-won/Desktop/오늘얼마?/오늘얼마?/오늘얼마?.xcodeproj/project.pbxproj"

try:
    with open(project_path, 'r') as f:
        content = f.read()

    # Release Configuration ID for the Main Target (from previous view_file output)
    # The ID is 2AF412662F31180F0011864D
    
    release_config_pattern = r'(2AF412662F31180F0011864D /\* Release \*/ = \{.*?buildSettings = \{)(.*?)(?=\};)'
    
    def replacement_func(match):
        header = match.group(1)
        settings = match.group(2)
        
        # Remove existing settings to avoid duplicates
        settings = re.sub(r'CODE_SIGN_STYLE = .*?;', '', settings)
        settings = re.sub(r'CODE_SIGN_IDENTITY = .*?;', '', settings)
        settings = re.sub(r'"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = .*?;', '', settings)
        settings = re.sub(r'PROVISIONING_PROFILE_SPECIFIER = .*?;', '', settings)
        settings = re.sub(r'"PROVISIONING_PROFILE_SPECIFIER\[sdk=iphoneos\*\]" = .*?;', '', settings)
        
        # Add manual settings
        new_settings = settings + '\n' + \
            '\t\t\t\tCODE_SIGN_STYLE = Manual;\n' + \
            '\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";\n' + \
            '\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";\n' + \
            '\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = HowMuchToday_AppStore_Manual;\n' + \
            '\t\t\t\t"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" = HowMuchToday_AppStore_Manual;\n' + \
            '\t\t\t\tDEVELOPMENT_TEAM = YA6CU6MN98;\n' + \
            '\t\t\t\t"DEVELOPMENT_TEAM[sdk=iphoneos*]" = YA6CU6MN98;\n'
            
        return header + new_settings

    new_content = re.sub(release_config_pattern, replacement_func, content, flags=re.DOTALL)
    
    with open(project_path, 'w') as f:
        f.write(new_content)
        
    print("✅ Successfully applied Manual Signing settings to Release configuration.")

except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
