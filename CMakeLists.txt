cmake_minimum_required(VERSION 3.5)

if(MSVC)
    # compile using the static runtime
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

project(steam_voice)

set(SOURCE_FILES
    src/main.cpp
	src/pipes.h src/pipes_win.cpp src/pipes_linux.cpp
	src/ThreadSafeInt.h src/ThreadSafeInt.cpp
	src/ThreadInputBuffer.h src/ThreadInputBuffer.cpp
	src/SteamVoiceEncoder.h src/SteamVoiceEncoder.cpp
	src/CommandQueue.h src/CommandQueue.cpp
	src/stream_mp3.h src/stream_mp3.cpp
	src/util.h src/util.cpp
	src/pid.h src/pid.cpp
	src/crc32.h src/crc32.cpp
	src/ChatSoundConverter.h src/ChatSoundConverter.cpp
)

include_directories(src)
include_directories(include)
link_directories(lib)

if(MSVC)	
	# Disable C++ exceptions
	#string(REPLACE "/EHsc" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    set(LINK_LIBS ${CMAKE_CURRENT_LIST_DIR}/lib/opus.lib
				  ${CMAKE_CURRENT_LIST_DIR}/lib/zita-resampler.lib)

else()
    set(CMAKE_CXX_FLAGS "-Wall")
    set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
    set(CMAKE_CXX_FLAGS_RELEASE "-Os -fno-exceptions -w -Wfatal-errors")

    set(LINK_LIBS -lopus -lpthread ${CMAKE_SOURCE_DIR}/lib/libzita-resampler.a)
endif()

add_executable(${PROJECT_NAME} ${SOURCE_FILES})

if (MSVC)
	set_property(TARGET ${PROJECT_NAME} PROPERTY VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/lib")
	set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

target_link_libraries(${PROJECT_NAME} ${LINK_LIBS} ${OPTIONS})

set_target_properties(${PROJECT_NAME} PROPERTIES
                      RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_CURRENT_LIST_DIR}/lib
                      RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_CURRENT_LIST_DIR}/lib
)
