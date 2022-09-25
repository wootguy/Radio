cmake_minimum_required(VERSION 3.6)

set(SVEN_ROOT_PATH "C:/Games/Steam/steamapps/common/Sven Co-op" CACHE FILEPATH "Where your Sven Co-op folder is")
set(DLL_INSTALL_PATH "svencoop/addons/metamod/dlls" CACHE FILEPATH "Where to install the DLL (relative to Sven Co-op folder)")

project(Radio)

set(SOURCE_FILES 
	src/meta/api_info.cpp
	src/meta/api_info.h
	src/meta/dllapi.cpp
	src/meta/dllapi_post.cpp
	src/meta/dllapi_post.h
	src/meta/engine_api.cpp
	src/meta/engine_api_post.cpp
	src/meta/engine_api_post.h
	src/meta/h_export.cpp
	src/meta/log_plugin.cpp
	src/meta/log_plugin.h
	src/meta/meta_api.cpp
	src/meta/plugin.cpp
	src/meta/plugin.h
	src/meta/sdk_util.cpp
	src/meta/trace_api.cpp
	src/meta/trace_api.h
	src/meta/vdate.cpp
	
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

if(MSVC)	
	set_target_properties(${PROJECT_NAME} PROPERTIES
					  VS_DEBUGGER_COMMAND "svencoop.exe"
					  VS_DEBUGGER_COMMAND_ARGUMENTS "+map stadium4"
					  VS_DEBUGGER_WORKING_DIRECTORY "${SVEN_ROOT_PATH}/${DLL_INSTALL_PATH}")

else()
	set(CMAKE_CXX_FLAGS "-Wall -std=c++11")
	set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
	set(CMAKE_CXX_FLAGS_RELEASE "-Os -fno-exceptions -w -Wfatal-errors")
endif()
