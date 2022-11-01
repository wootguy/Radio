cmake_minimum_required(VERSION 3.6)

set(SVEN_ROOT_PATH "C:/Games/Steam/steamapps/common/Sven Co-op/" CACHE FILEPATH "Where your Sven Co-op folder is")
set(DLL_INSTALL_PATH "svencoop/addons/metamod/dlls" CACHE FILEPATH "Where to install the DLL (relative to Sven Co-op folder)")

project(Radio)

set(SOURCE_FILES
	src/radio.h src/radio.cpp
	src/Channel.h src/Channel.cpp
	src/menus.h src/menus.cpp
	src/FakeMic.h src/FakeMic.cpp
	src/radio_utils.h src/radio_utils.cpp
	src/meta_utils.h src/meta_utils.cpp
	src/meta_init.h src/meta_init.cpp
	src/Scheduler.h src/Scheduler.cpp
	src/TextMenu.h src/TextMenu.cpp
	src/PlayerState.h src/PlayerState.cpp
	src/Song.h src/Song.cpp
	src/network_threads.h src/network_threads.cpp
	src/message_overrides.h src/message_overrides.cpp
	src/ThreadSafeQueue.h src/ThreadSafeQueue.cpp
	src/mstream.h src/mstream.cpp
	src/net/Packet.h src/net/Packet.cpp
	src/net/IPV4.h src/net/IPV4.cpp
	src/net/Socket.h
	src/tts_langs.cpp
)

if(MSVC)
	set(SOURCE_FILES
		${SOURCE_FILES}
		src/net/Socket_win.cpp
		src/net/network_win.cpp
	)	
else()
	set(SOURCE_FILES
		${SOURCE_FILES}
		src/net/Socket_unix.cpp
		src/net/network_unix.cpp
	)
endif()

include_directories(src)
include_directories(src/net)
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
					  VS_STARTUP_PROJECT ${PROJECT_NAME}
					  VS_DEBUGGER_COMMAND "svencoop.exe"
					  VS_DEBUGGER_COMMAND_ARGUMENTS "+map stadium4 -nomsaa -nofbo -noborder -condebug"
					  VS_DEBUGGER_WORKING_DIRECTORY "${SVEN_ROOT_PATH}")
	
	source_group("Header Files\\net" FILES Socket.h Packet.h IPV4.h)
	source_group("Source Files\\net" FILES Socket_win.cpp network_win.cpp Packet.cpp IPV4.cpp) 
					  
	target_link_libraries(${PROJECT_NAME} WS2_32 IPHLPAPI)
	
	# can't overwrite dll while its loaded but it can be renamed, then you can run "meta reload <plugin>" to update it in-game				
	add_custom_command(TARGET ${PROJECT_NAME}  PRE_BUILD
		COMMAND ${CMAKE_CURRENT_LIST_DIR}/replace_dll.bat
	)

else()
	target_compile_definitions(${PROJECT_NAME} PUBLIC -Dlinux)
	set(CMAKE_CXX_FLAGS "-Wall -std=c++11 -m32")
	set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
	set(CMAKE_CXX_FLAGS_RELEASE "-Os -fno-exceptions -w -Wfatal-errors")
endif()
