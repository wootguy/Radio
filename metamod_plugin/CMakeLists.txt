cmake_minimum_required(VERSION 3.6)

set(SVEN_ROOT_PATH "C:/Games/Steam/steamapps/common/Sven Co-op/" CACHE FILEPATH "Where your Sven Co-op folder is")
set(DLL_INSTALL_PATH "svencoop/addons/metamod/dlls" CACHE FILEPATH "Where to install the DLL (relative to Sven Co-op folder)")

project(Radio)

set(SOURCE_FILES
	src/meta/h_export.cpp
	src/meta/sdk_util.cpp
	src/meta/meta_util.h src/meta/meta_util.cpp
	
	src/radio.cpp
)

include_directories(src)
include_directories(src/meta)
include_directories(include/metamod)
include_directories(include/hlsdk/common)
include_directories(include/hlsdk/dlls)
include_directories(include/hlsdk/engine)
include_directories(include/hlsdk/pm_shared)

add_library(${PROJECT_NAME} SHARED ${SOURCE_FILES})

set_target_properties(${PROJECT_NAME} PROPERTIES
                      RUNTIME_OUTPUT_DIRECTORY_DEBUG "${SVEN_ROOT_PATH}/${DLL_INSTALL_PATH}"
                      RUNTIME_OUTPUT_DIRECTORY_RELEASE "${SVEN_ROOT_PATH}/${DLL_INSTALL_PATH}")
				
# can't overwrite dll while its loaded but it can be renamed, then you can run "meta reload <plugin>" to update it in-game				
add_custom_command(TARGET ${PROJECT_NAME}  PRE_BUILD
    COMMAND ${CMAKE_CURRENT_LIST_DIR}/replace_dll.bat
)

if(MSVC)
	source_group("Source Files\\meta" FILES	src/meta/dllapi.cpp
											src/meta/engine_api.cpp
											src/meta/h_export.cpp
											src/meta/meta_api.cpp
											src/meta/sdk_util.cpp)
											
	set_target_properties(${PROJECT_NAME} PROPERTIES
					  VS_STARTUP_PROJECT ${PROJECT_NAME}
					  VS_DEBUGGER_COMMAND "svencoop.exe"
					  VS_DEBUGGER_COMMAND_ARGUMENTS "+map stadium4 -nomsaa -nofbo -noborder -condebug"
					  VS_DEBUGGER_WORKING_DIRECTORY "${SVEN_ROOT_PATH}")

else()
	set(CMAKE_CXX_FLAGS "-Wall -std=c++11")
	set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
	set(CMAKE_CXX_FLAGS_RELEASE "-Os -fno-exceptions -w -Wfatal-errors")
endif()
