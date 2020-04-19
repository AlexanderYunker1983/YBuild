# The general module for an assembly system of projects

get_property(YBUILD_INCLUSION_REGISTERED GLOBAL PROPERTY YBUILD_INCLUDED DEFINED)
if(YBUILD_INCLUSION_REGISTERED)
    return()
endif(YBUILD_INCLUSION_REGISTERED)

include(JSONParser)

find_package(Subversion QUIET)
include(MacroAddFileDependencies)
set(CMAKE_ALLOW_LOOSE_LOOP_CONSTRUCTS true)

include(${CMAKE_BINARY_DIR}/3rdparty.cmake)
include(${CMAKE_BINARY_DIR}/spread.cmake)

################################################
# YBUILD_ESCAPE
function(YBUILD_ESCAPE var)
    set(RESULT "${ARGN}")
    string(REPLACE "\\" "\\\\" RESULT "${ARGN}")
    string(REPLACE "\$" "\\\$" RESULT "${RESULT}")
    string(REPLACE "\(" "\\\(" RESULT "${RESULT}")
    string(REPLACE "\)" "\\\)" RESULT "${RESULT}")
    string(REPLACE "\#" "\\\#" RESULT "${RESULT}")
    string(REPLACE "\^" "\\\^" RESULT "${RESULT}")
    set(${var} "${RESULT}" PARENT_SCOPE)
endfunction(YBUILD_ESCAPE)

################################################
# YBUILD_INVOKE
function(YBUILD_INVOKE fn)
    YBUILD_ESCAPE(ESCAPED_ARGN "${ARGN}")
    get_property(CTR GLOBAL PROPERTY YBUILD_INVOCATION_COUNTER)
    set(TMPNAME "${CMAKE_BINARY_DIR}/ybuild_invoke_temp_${CTR}.cmake")
    file(WRITE "${TMPNAME}" "${fn}(\"${ESCAPED_ARGN}\")")
    include("${TMPNAME}")
    math(EXPR CTR "${CTR} + 1")
    set_property(GLOBAL PROPERTY YBUILD_INVOCATION_COUNTER "${CTR}")
endfunction(YBUILD_INVOKE)

################################################
# YBUILD_IS_LIBRARY_REGISTERED
function(YBUILD_IS_LIBRARY_REGISTERED lib var)
    get_property(YBUILD_REGISTERED_LIBRARY_NAMES GLOBAL PROPERTY YBUILD_REGISTERED_LIBRARY_NAMES)
    list(FIND YBUILD_REGISTERED_LIBRARY_NAMES "${lib}" LIBRARY_INDEX)
    if(LIBRARY_INDEX EQUAL -1)
        set(${var} OFF PARENT_SCOPE)
    else(LIBRARY_INDEX EQUAL -1)
        set(${var} ON PARENT_SCOPE)
    endif(LIBRARY_INDEX EQUAL -1)
endfunction(YBUILD_IS_LIBRARY_REGISTERED)

################################################
# YBUILD_LINK_REGISTERED_LIBRARY
function(YBUILD_LINK_REGISTERED_LIBRARY target lib)
    get_property(YBUILD_REGISTERED_LIBRARY_NAMES GLOBAL PROPERTY YBUILD_REGISTERED_LIBRARY_NAMES)
    get_property(YBUILD_REGISTERED_LIBRARY_ACTIONS GLOBAL PROPERTY YBUILD_REGISTERED_LIBRARY_ACTIONS)
    list(FIND YBUILD_REGISTERED_LIBRARY_NAMES "${lib}" LIBRARY_INDEX)
    list(GET YBUILD_REGISTERED_LIBRARY_ACTIONS ${LIBRARY_INDEX} LIBRARY_ACTION)
    YBUILD_INVOKE(${LIBRARY_ACTION} "${target}")
endfunction(YBUILD_LINK_REGISTERED_LIBRARY)

################################################
# YBUILD_LINK_LIBRARIES
function(YBUILD_LINK_LIBRARIES target)
    set(WIN32_ONLY_LIBRARIES ws2_32 rpcrt4 ole32 winmm dxerr8 strmiids vfw32 wmvcore shlwapi)
    set(UNIX_ONLY_LIBRARIES pthread dl rt)
    
    foreach(lib ${ARGN})
        string(TOLOWER "${lib}" LIB_LOWER)
        set(IGNORE_LIB OFF)
        if(WIN32)
            list(FIND UNIX_ONLY_LIBRARIES "${lib}" UNIX_ONLY_LIBRARY_FOUND)
            if(NOT UNIX_ONLY_LIBRARY_FOUND EQUAL -1)
                set(IGNORE_LIB ON)
            endif(NOT UNIX_ONLY_LIBRARY_FOUND EQUAL -1)
        elseif(UNIX)
            list(FIND WIN32_ONLY_LIBRARIES "${LIB_LOWER}" WIN32_ONLY_LIBRARY_FOUND)
            if(NOT WIN32_ONLY_LIBRARY_FOUND EQUAL -1)
                set(IGNORE_LIB ON)
            endif(NOT WIN32_ONLY_LIBRARY_FOUND EQUAL -1)
        endif(WIN32)
        
        if(NOT IGNORE_LIB)
            YBUILD_IS_LIBRARY_REGISTERED("${lib}" LIBRARY_REGISTERED)
            if(LIBRARY_REGISTERED)
                YBUILD_LINK_REGISTERED_LIBRARY("${target}" "${lib}")
            else(LIBRARY_REGISTERED)
                target_link_libraries(${target} "${lib}")
            endif(LIBRARY_REGISTERED)
        endif(NOT IGNORE_LIB)
    endforeach(lib)
endfunction(YBUILD_LINK_LIBRARIES)

################################################
# YBUILD_REGISTER_LIBRARY
function(YBUILD_REGISTER_LIBRARY name action)
    set_property(GLOBAL APPEND PROPERTY YBUILD_REGISTERED_LIBRARY_NAMES "${name}")
    set_property(GLOBAL APPEND PROPERTY YBUILD_REGISTERED_LIBRARY_ACTIONS "${action}")
endfunction(YBUILD_REGISTER_LIBRARY)

################################################
# YBUILD_GET_VERSION_INFO
function(YBUILD_GET_VERSION_INFO)
    execute_process(
        COMMAND "${CMAKE_SOURCE_DIR}/YBuild/bin/GitVersion/GitVersion.exe"
        OUTPUT_VARIABLE output_json
        ERROR_VARIABLE error
        RESULT_VARIABLE result
        OUTPUT_STRIP_TRAILING_WHITESPACE)
        
    sbeParseJson(json output_json)
    
    set(VERSION_SHORT "${json.MajorMinorPatch}")
    set(YBUILD_FULL_SEM_VERSION "${json.FullSemVer}" PARENT_SCOPE)
    set(YBUILD_SHA_VERSION "${json.Sha}" PARENT_SCOPE)
    
    set(YBUILD_PRODUCT_VERSION_SHORT "${VERSION_SHORT}" PARENT_SCOPE)
    set(PRODUCT_VERSION "${VERSION_SHORT}")
    set(YBUILD_PRODUCT_VERSION "${PRODUCT_VERSION}" PARENT_SCOPE)
    set(YBUILD_PRODUCT_VERSION_DOTNET "${PRODUCT_VERSION}" PARENT_SCOPE)

    string(REPLACE . , VERSION_RC "${PRODUCT_VERSION}")
    set(YBUILD_PRODUCT_VERSION_RC "${VERSION_RC}" PARENT_SCOPE)

endfunction(YBUILD_GET_VERSION_INFO)

################################################
# YBUILD_SET_COMMON_COMPILE_FLAGS
function(YBUILD_SET_COMMON_COMPILE_FLAGS)
    if(MSVC)
        set(CXX_FLAGS "")

        # Добавим во все конфигурации сборку .pdb. 
        set(CXX_FLAGS "${CXX_FLAGS} /Zi")

        # Уберем включение системных include-каталогов.
        set(CXX_FLAGS "${CXX_FLAGS} /X")

        # Включим intrinsics.
        set(CXX_FLAGS "${CXX_FLAGS} /Oi")
        
        # Отключим некоторые варнинги
        set(CXX_FLAGS "${CXX_FLAGS} /wd4250") # 'class' : inherits 'method' via dominance
        set(CXX_FLAGS "${CXX_FLAGS} /wd4251") # 'class1' needs to have dll-interface to be used by clients of 'class1'
        set(CXX_FLAGS "${CXX_FLAGS} /wd4275") # non dll-interface class 'class1' used as base for dll-interface class 'class2'
        set(CXX_FLAGS "${CXX_FLAGS} /wd4065") # switch statement contains 'default' but no 'case' labels
        set(CXX_FLAGS "${CXX_FLAGS} /wd4627") # '<identifier>': skipped when looking for precompiled header use
        
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CXX_FLAGS}" PARENT_SCOPE)
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${CXX_FLAGS}" PARENT_SCOPE)
    endif(MSVC)
    
    if(UNIX)
        add_definitions(-DLINUX)
        add_definitions(-D_FILE_OFFSET_BITS=64)
        add_definitions(-D__STDC_LIMIT_MACROS)
        add_definitions(-D_GNU_SOURCE)
        add_definitions(-D_REENTRANT)
    endif(UNIX)
endfunction(YBUILD_SET_COMMON_COMPILE_FLAGS)

################################################
# YBUILD_GET_FILE_NAME
function(YBUILD_GET_FILE_NAME path var)
    file(TO_CMAKE_PATH "${path}" CANONICAL_PATH)
    string(REGEX REPLACE "^.*/([^/]*)$" \\1 FILENAME "${CANONICAL_PATH}")
    set(${var} "${FILENAME}" PARENT_SCOPE)
endfunction(YBUILD_GET_FILE_NAME)

################################################
# YBUILD_CONFIGURE_FILE
function(YBUILD_CONFIGURE_FILE inpath var)
    if(ARGC GREATER 2)
        list(GET ARGN 0 TARGET_DIR)
        YBUILD_GET_FILE_NAME("${inpath}" INNAME)
        string(REGEX REPLACE "^(.*)\\.in\$" \\1 TARGETNAME "${INNAME}")
        set(TARGETPATH "${TARGET_DIR}/${TARGETNAME}")
    else(ARGC GREATER 2)
        string(REGEX REPLACE "^(.*)\\.in\$" \\1 TARGETPATH "${inpath}")
    endif(ARGC GREATER 2)

    configure_file("${inpath}" "${TARGETPATH}" ESCAPE_QUOTES)
    set(${var} "${TARGETPATH}" PARENT_SCOPE)
endfunction(YBUILD_CONFIGURE_FILE)

################################################
# YBUILD_FORCE_INCLUDE_FILE
macro(YBUILD_FORCE_INCLUDE_FILE path)
    if(MSVC)
        set(FORCE_INCLUDES "${FORCE_INCLUDES} /FI\"${path}\"")
    else(MSVC)
        set(FORCE_INCLUDES "${FORCE_INCLUDES} -include ${path}")
    endif(MSVC)
endmacro(YBUILD_FORCE_INCLUDE_FILE)

################################################
# YBUILD_CONFIGURE_C_VERSION_FILE
macro(YBUILD_CONFIGURE_C_VERSION_FILE vpath)
    YBUILD_CONFIGURE_FILE("${vpath}" CONFIGURED_FILE_PATH "${CMAKE_CURRENT_BINARY_DIR}")
    YBUILD_FORCE_INCLUDE_FILE("${CONFIGURED_FILE_PATH}")
    include_directories("${CMAKE_CURRENT_BINARY_DIR}")
endmacro(YBUILD_CONFIGURE_C_VERSION_FILE)

################################################
# YBUILD_CONFIGURE_JAVA_VERSION_FILE
macro(YBUILD_CONFIGURE_JAVA_VERSION_FILE vpath)
    YBUILD_CONFIGURE_FILE("${vpath}" CONFIGURED_FILE_PATH)
endmacro(YBUILD_CONFIGURE_JAVA_VERSION_FILE)

################################################
# YBUILD_CONFIGURE_CONFIGURAYION_FILE
macro(YBUILD_CONFIGURE_CONFIGURATION_FILE vpath)
    YBUILD_CONFIGURE_FILE("${vpath}" CONFIGURED_FILE_PATH)
    YBUILD_FORCE_INCLUDE_FILE("${CMAKE_BINARY_DIR}/${CONFIGURED_FILE_PATH}")
endmacro(YBUILD_CONFIGURE_CONFIGURATION_FILE vpath)


################################################
# YBUILD_SET_STATIC_CRT_LINKAGE
macro(YBUILD_SET_STATIC_CRT_LINKAGE)
    foreach(flag_var
            CMAKE_CXX_FLAGS CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_RELEASE
            CMAKE_CXX_FLAGS_MINSIZEREL CMAKE_CXX_FLAGS_RELWITHDEBINFO
            CMAKE_C_FLAGS CMAKE_C_FLAGS_DEBUG CMAKE_C_FLAGS_RELEASE
            CMAKE_C_FLAGS_MINSIZEREL CMAKE_C_FLAGS_RELWITHDEBINFO)
        if(${flag_var} MATCHES "/MD")
            string(REGEX REPLACE "/MD" "/MT" ${flag_var} "${${flag_var}}")
        endif(${flag_var} MATCHES "/MD")
        if(${flag_var} MATCHES "/MDd")
            string(REGEX REPLACE "/MDd" "/MTd" ${flag_var} "${${flag_var}}")
        endif(${flag_var} MATCHES "/MDd")
    endforeach(flag_var)
    set(STATIC_CRT_LINKAGE 1)
endmacro(YBUILD_SET_STATIC_CRT_LINKAGE)

################################################
# YBUILD_ADD_3RDPARTY_DIRECTORIES
function(YBUILD_ADD_3RDPARTY_DIRECTORIES)
    link_directories("${YBUILD_FULL_LIBRARY_OUTPUT_DIRECTORY}")
    
    foreach(tpname ${YBUILD_TPLIBS_NAME})
        YBUILD_GET_TPLIB_DIR(tpdir ${tpname})
        link_directories("${YBUILD_3RDPARTY_LIBRARY_DIR}/${tpdir}")
    endforeach(tpname)
    
    if(EXISTS "${CMAKE_SOURCE_DIR}/YLib")
        include_directories("${CMAKE_SOURCE_DIR}/YLib/include")
    endif(EXISTS "${CMAKE_SOURCE_DIR}/YLib")

    if(EXISTS "${CMAKE_SOURCE_DIR}/YStor")
        include_directories("${CMAKE_SOURCE_DIR}/YStor/include")
    endif(EXISTS "${CMAKE_SOURCE_DIR}/YStor")
    
    if(EXISTS "${CMAKE_SOURCE_DIR}/NoiseFilterLib")
        include_directories("${CMAKE_SOURCE_DIR}/NoiseFilterLib/include")
    endif(EXISTS "${CMAKE_SOURCE_DIR}/NoiseFilterLib")      

    if(COMMAND YBUILD_TPLIB_ASIOSDK_EXISTS)
        include_directories("${YBUILD_TPLIB_ASIOSDK_PATH}")
        include_directories("${YBUILD_TPLIB_ASIOSDK_PATH}/host/pc")
    endif()

    if(COMMAND YBUILD_TPLIB_PUGIXML_EXISTS)	
        include_directories("${YBUILD_TPLIB_PUGIXML_PATH}/src")
    endif() 

    if(COMMAND YBUILD_TPLIB_GTEST_EXISTS)
        include_directories("${YBUILD_TPLIB_GTEST_PATH}/include")
    endif()

    if(COMMAND YBUILD_TPLIB_GMOCK_EXISTS)
        include_directories("${YBUILD_TPLIB_GMOCK_PATH}/include")
    endif()
    
    if(COMMAND YBUILD_TPLIB_AGENT-PP_EXISTS)
        include_directories("${YBUILD_TPLIB_AGENT-PP_PATH}/agent++_4.0.0/include/system")
        include_directories("${YBUILD_TPLIB_AGENT-PP_PATH}/snmp++_3.3.0/include/system")
        include_directories("${YBUILD_TPLIB_AGENT-PP_PATH}/agent++_4.0.0/include")
        include_directories("${YBUILD_TPLIB_AGENT-PP_PATH}/snmp++_3.3.0/include")
    endif()

    if(COMMAND YBUILD_TPLIB_LIBJASPER_EXISTS)
        include_directories("${YBUILD_TPLIB_LIBJASPER_PATH}/include")
    endif()

    if(COMMAND YBUILD_TPLIB_MP4V2_EXISTS)
        include_directories("${YBUILD_TPLIB_MP4V2_PATH}")
        include_directories("${YBUILD_TPLIB_MP4V2_PATH}/include")
    endif()

    if(COMMAND YBUILD_TPLIB_TBB_EXISTS)
        include_directories("${YBUILD_TPLIB_TBB_PATH}/include")
    endif()

    if(COMMAND YBUILD_TPLIB_XERCESC_EXISTS)
        include_directories("${YBUILD_TPLIB_XERCESC_PATH}/include")
    endif()

    if(COMMAND YBUILD_TPLIB_PUGIXML_EXISTS)
        include_directories("${YBUILD_TPLIB_PUGIXML_PATH}")
    endif()
    
    if(COMMAND YBUILD_TPLIB_AES_EXISTS)
        include_directories("${YBUILD_TPLIB_AES_PATH}")
    endif()
    
    if(COMMAND YBUILD_TPLIB_LIBRTMP_EXISTS)
        include_directories("${YBUILD_TPLIB_LIBRTMP_PATH}/include")
    endif()

    if(COMMAND YBUILD_TPLIB_DB_EXISTS)
        include_directories("${YBUILD_TPLIB_DB_PATH}/dbinc")
        if(UNIX)
            include_directories("${YBUILD_TPLIB_DB_PATH}/build_unix")
        elseif(WIN32)
            include_directories("${YBUILD_TPLIB_DB_PATH}/build_windows")
        endif(UNIX)
    endif()

    if(COMMAND YBUILD_TPLIB_PROTOBUF_EXISTS)
        include_directories("${YBUILD_TPLIB_PROTOBUF_PATH}/include")
    endif()

    if(COMMAND YBUILD_TPLIB_LEVELDB_EXISTS)
        include_directories("${YBUILD_TPLIB_LEVELDB_PATH}/include")
    endif()
    
    if(COMMAND YBUILD_TPLIB_GPSNMEA_EXISTS)
        include_directories("${YBUILD_TPLIB_GPSNMEA_PATH}/include")
    endif()
    
    if(COMMAND YBUILD_TPLIB_CATCH_EXISTS)
        include_directories("${YBUILD_TPLIB_CATCH_PATH}/include")
    endif()

    if(COMMAND YBUILD_TPLIB_LIVE555_EXISTS)
        include_directories("${YBUILD_TPLIB_LIVE555_PATH}/include")
        # ниже инклюды для внутренностей live555, не использовать их извне
        include_directories("${YBUILD_TPLIB_LIVE555_PATH}/live/BasicUsageEnvironment/include")
        include_directories("${YBUILD_TPLIB_LIVE555_PATH}/live/groupsock/include")
        include_directories("${YBUILD_TPLIB_LIVE555_PATH}/live/liveMedia/include")
        include_directories("${YBUILD_TPLIB_LIVE555_PATH}/live/UsageEnvironment/include")
    endif()

    if(COMMAND YBUILD_TPLIB_BOOST_EXISTS)
        include_directories("${YBUILD_TPLIB_BOOST_PATH}")
        link_directories("${YBUILD_TPLIB_BOOST_PATH}/stage/lib")
        YBUILD_REGISTER_LIBRARY(boost_thread YBUILD_LINK_BOOST_THREAD)
    endif()

    if(COMMAND YBUILD_TPLIB_BOOST-WINDOWS_EXISTS)
        include_directories("${YBUILD_TPLIB_BOOST-WINDOWS_PATH}")
        link_directories("${YBUILD_TPLIB_BOOST-WINDOWS_PATH}/stage/lib")
    endif()
    
    if(COMMAND YBUILD_TPLIB_FTD2XX_EXISTS)
        include_directories("${YBUILD_TPLIB_FTD2XX_PATH}/include")
        link_directories("${YBUILD_TPLIB_FTD2XX_PATH}/lib/x86")
        YBUILD_REGISTER_LIBRARY(ftd2xx YBUILD_LINK_FTD2XX)
    endif()

    if(COMMAND YBUILD_TPLIB_LOG4C_EXISTS)
        include_directories("${YBUILD_TPLIB_LOG4C_PATH}")
    endif()

    if(COMMAND YBUILD_TPLIB_CPPUNIT_EXISTS)
        include_directories("${YBUILD_TPLIB_CPPUNIT_PATH}/include")
    endif()
        
    if(COMMAND YBUILD_TPLIB_ORBACUS_EXISTS)
        include_directories("${YBUILD_TPLIB_ORBACUS_PATH}/include")
    endif()

    if(COMMAND YBUILD_TPLIB_SQLITE_EXISTS)
        include_directories("${YBUILD_TPLIB_SQLITE_PATH}")
    endif()

    if(WIN32)
        if(COMMAND YBUILD_TPLIB_DIRECTX_EXISTS)
            include_directories("${YBUILD_TPLIB_DIRECTX_PATH}/include")
            link_directories("${YBUILD_TPLIB_DIRECTX_PATH}/lib")
        endif()

        if(COMMAND YBUILD_TPLIB_DSHOWBASE_EXISTS)
            include_directories("${YBUILD_TPLIB_DSHOWBASE_PATH}/include")
        endif()

    endif(WIN32)
    
    if(MSVC)

        if(COMMAND YBUILD_TPLIB_WK_EXISTS)
            include_directories("${YBUILD_TPLIB_WK_PATH}/Include/um")
            include_directories("${YBUILD_TPLIB_WK_PATH}/Include/shared")
            include_directories("${YBUILD_TPLIB_WK_PATH}/Include/winrt")

            link_directories("${YBUILD_TPLIB_WK_PATH}/Lib/winv6.3/um/\$(PlatformTarget)")
        endif()
        
        if(COMMAND YBUILD_TPLIB_WK10_EXISTS)
            include_directories("${YBUILD_TPLIB_WK10_PATH}/Include/um")
            include_directories("${YBUILD_TPLIB_WK10_PATH}/Include/shared")
            include_directories("${YBUILD_TPLIB_WK10_PATH}/Include/winrt")
            include_directories("${YBUILD_TPLIB_WK10_PATH}/Include/ucrt")
            if(YWIN64) 
                link_directories("${YBUILD_TPLIB_WK10_PATH}/Lib/ucrt/x64")
                link_directories("${YBUILD_TPLIB_WK10_PATH}/Lib/um/x64")
            else()
                link_directories("${YBUILD_TPLIB_WK10_PATH}/Lib/ucrt/x86")
                link_directories("${YBUILD_TPLIB_WK10_PATH}/Lib/um/x86")
            endif()
        endif()
        
        if(COMMAND YBUILD_TPLIB_VSCRT8_EXISTS)
            set(VSCRT "${YBUILD_TPLIB_VSCRT8_PATH}")
        endif()

        if(COMMAND YBUILD_TPLIB_VSCRT9_EXISTS)
            set(VSCRT "${YBUILD_TPLIB_VSCRT9_PATH}")
        endif()
        
        if(COMMAND YBUILD_TPLIB_VSCRT10_EXISTS)
            set(VSCRT "${YBUILD_TPLIB_VSCRT10_PATH}")
        endif()

        if(COMMAND YBUILD_TPLIB_VSCRT12_EXISTS)
            set(VSCRT "${YBUILD_TPLIB_VSCRT12_PATH}")
        endif()
        
        if(COMMAND YBUILD_TPLIB_VSCRT14_EXISTS)
            set(VSCRT "${YBUILD_TPLIB_VSCRT14_PATH}")
        endif()
        
        if(COMMAND YBUILD_TPLIB_VSCRT15_EXISTS)
            set(VSCRT "${YBUILD_TPLIB_VSCRT15_PATH}")
        endif()

        if(COMMAND YBUILD_TPLIB_VSCRT16_EXISTS)
            set(VSCRT "${YBUILD_TPLIB_VSCRT16_PATH}")
        endif()

        if(DEFINED VSCRT AND YWIN64)
            add_definitions(-DX64)
            include_directories("${VSCRT}/include")
            link_directories("${VSCRT}/lib/amd64")
            YBUILD_REGISTER_LIBRARY(comsuppw YBUILD_LINK_COMSUPPW)
        elseif(DEFINED VSCRT)
            include_directories("${VSCRT}/include")
            link_directories("${VSCRT}/lib")
            YBUILD_REGISTER_LIBRARY(comsuppw YBUILD_LINK_COMSUPPW)
        else()
        endif()
    endif(MSVC)
    
    if(WIN32)
        if(COMMAND YBUILD_TPLIB_AMP-FFT_EXISTS)
            include_directories("${YBUILD_TPLIB_AMP-FFT_PATH}")
            YBUILD_REGISTER_LIBRARY(amp-fft YBUILD_LINK_AMPFFT)
        endif()

        if(COMMAND YBUILD_TPLIB_BOTAN_EXISTS)
            include_directories("${YBUILD_3RDPARTY_LIBRARY_DIR}/botan_1.10.8/build/include")
        endif()

        if(COMMAND YBUILD_TPLIB_ATLMFC8_EXISTS)
            set(ATLMFC "${YBUILD_TPLIB_ATLMFC8_PATH}")
        endif()

        if(COMMAND YBUILD_TPLIB_ATLMFC9_EXISTS)
            set(ATLMFC "${YBUILD_TPLIB_ATLMFC9_PATH}")
        endif()
        
        if(COMMAND YBUILD_TPLIB_ATLMFC10_EXISTS)
            set(ATLMFC "${YBUILD_TPLIB_ATLMFC10_PATH}")
        endif()
        
        if(COMMAND YBUILD_TPLIB_ATLMFC12_EXISTS)
            set(ATLMFC "${YBUILD_TPLIB_ATLMFC12_PATH}")
        endif()

        if(COMMAND YBUILD_TPLIB_ATLMFC14_EXISTS)
            set(ATLMFC "${YBUILD_TPLIB_ATLMFC14_PATH}")
        endif()
        
        if(DEFINED ATLMFC)
            include_directories("${ATLMFC}/include")
            link_directories("${ATLMFC}/lib")
        endif()

        if(COMMAND YBUILD_TPLIB_WTL_EXISTS)
            include_directories("${YBUILD_TPLIB_WTL_PATH}/include")
        endif()
        
        if(COMMAND YBUILD_TPLIB_WMSDK_EXISTS)
            include_directories("${YBUILD_TPLIB_WMSDK_PATH}/include")
            link_directories("${YBUILD_TPLIB_WMSDK_PATH}/lib")
        endif()

        if(COMMAND YBUILD_TPLIB_PSDK_EXISTS)
            include_directories("${YBUILD_TPLIB_PSDK_PATH}/include")
            link_directories("${YBUILD_TPLIB_PSDK_PATH}/lib")
        endif()

        if(COMMAND YBUILD_TPLIB_FFMPEG_EXISTS)
            include_directories("${YBUILD_TPLIB_FFMPEG_PATH}/include")
            link_directories("${YBUILD_TPLIB_FFMPEG_PATH}/lib")
            if(COMMAND YBUILD_TPLIB_FFMPEG_11_06_2015_EXISTS)
                YBUILD_REGISTER_LIBRARY(ffmpeg YBUILD_LINK_FFMPEG2)
            elseif(COMMAND YBUILD_TPLIB_FFMPEG_4_0_1_EXISTS)
                YBUILD_REGISTER_LIBRARY(ffmpeg YBUILD_LINK_FFMPEG4)
            elseif(COMMAND YBUILD_TPLIB_FFMPEG_4_2_1_EXISTS)
                YBUILD_REGISTER_LIBRARY(ffmpeg YBUILD_LINK_FFMPEG4)
            else()
                YBUILD_REGISTER_LIBRARY(ffmpeg YBUILD_LINK_FFMPEG1)
            endif()
        endif()

        if(COMMAND YBUILD_TPLIB_IPP_EXISTS)
            include_directories("${YBUILD_TPLIB_IPP_PATH}/include")
            link_directories("${YBUILD_TPLIB_IPP_PATH}/lib")
            YBUILD_REGISTER_LIBRARY(ipp YBUILD_LINK_IPP)
        endif()
        
        if(COMMAND YBUILD_TPLIB_INTEL-MEDIA-SDK_EXISTS)
            include_directories("${YBUILD_TPLIB_INTEL-MEDIA-SDK_PATH}/include")
            link_directories("${YBUILD_TPLIB_INTEL-MEDIA-SDK_PATH}/lib")
            YBUILD_REGISTER_LIBRARY(hwcodecs YBUILD_LINK_HW_CODECS)
        endif()

        if(COMMAND YBUILD_TPLIB_CUDA-TOOLKIT_EXISTS)
            include_directories("${YBUILD_TPLIB_CUDA-TOOLKIT_PATH}/include")
            link_directories("${YBUILD_TPLIB_CUDA-TOOLKIT_PATH}/lib")
        endif()

        if(COMMAND YBUILD_TPLIB_MW10DEC_EXISTS)
            YBUILD_REGISTER_LIBRARY(mw10dec YBUILD_LINK_MW10_DECODER)
        endif()
        
        if(COMMAND YBUILD_TPLIB_AMWSDK_EXISTS)
            include_directories("${YBUILD_TPLIB_AMWSDK_PATH}/include")
            link_directories("${YBUILD_TPLIB_AMWSDK_PATH}/lib")
            YBUILD_REGISTER_LIBRARY(aw_adv601lib YBUILD_LINK_ADV601)
        endif()
        
        if(COMMAND YBUILD_TPLIB_WN95SCM_EXISTS)
            include_directories("${YBUILD_TPLIB_WN95SCM_PATH}/include")
            link_directories("${YBUILD_TPLIB_WN95SCM_PATH}/lib")
            YBUILD_REGISTER_LIBRARY(w95scm YBUILD_LINK_W95SCM)
        endif()

        if(COMMAND YBUILD_TPLIB_BASS_EXISTS)
            include_directories("${YBUILD_TPLIB_BASS_PATH}/include")
            link_directories("${YBUILD_TPLIB_BASS_PATH}/lib")
        endif()

        if(COMMAND YBUILD_TPLIB_MSWORD2000_EXISTS)
            include_directories("${YBUILD_TPLIB_MSWORD2000_PATH}")
        endif()
        
        if(COMMAND YBUILD_TPLIB_CYUSB_EXISTS)
            include_directories("${YBUILD_TPLIB_CYUSB_PATH}/include")
        endif()
        
        if(COMMAND YBUILD_TPLIB_NSP_EXISTS)
            include_directories("${YBUILD_TPLIB_NSP_PATH}/Include")
            link_directories("${YBUILD_TPLIB_NSP_PATH}/Msvc")
            YBUILD_REGISTER_LIBRARY(nsp YBUILD_LINK_NSP)
        endif()

        if(COMMAND YBUILD_TPLIB_NSIS_PLUGINAPI_EXISTS)
            include_directories("${YBUILD_TPLIB_NSIS_PLUGINAPI_PATH}")
        endif()
        
        if(COMMAND YBUILD_TPLIB_OPENCV_EXISTS)
            include_directories("${YBUILD_TPLIB_OPENCV_PATH}/include")
            link_directories("${YBUILD_TPLIB_OPENCV_PATH}/lib")
            YBUILD_REGISTER_LIBRARY(opencv YBUILD_LINK_OPENCV)
        endif()
    endif(WIN32)
endfunction(YBUILD_ADD_3RDPARTY_DIRECTORIES)

################################################
# YBUILD_ADD_3RDPARTY_COMPONENTS
function(YBUILD_ADD_3RDPARTY_COMPONENTS)
    foreach(lib ${YBUILD_TPLIBS_PATH})
        if(EXISTS "${lib}/CMakeLists.txt")
            get_filename_component(tpdirname "${lib}" NAME)
            add_subdirectory("${lib}" "${CMAKE_BINARY_DIR}/3rdparty/${tpdirname}" )
        endif()
    endforeach(lib)
endfunction(YBUILD_ADD_3RDPARTY_COMPONENTS)

################################################
# YBUILD_EXCLUDE_FILES
function(YBUILD_EXCLUDE_FILES lst)
    file(GLOB_RECURSE EXCL_SRCS ${ARGN})
    set(MYLIST "${${lst}}")
    
    foreach(src ${EXCL_SRCS})
        list(REMOVE_ITEM MYLIST "${src}")
    endforeach(src)
    
    set(${lst} "${MYLIST}" PARENT_SCOPE)
endfunction(YBUILD_EXCLUDE_FILES)

################################################
# YBUILD_INSTALL_3RDPARTY
function(YBUILD_INSTALL_3RDPARTY target)
    YBUILD_GET_TPLIB_DIR(tpdirname target)
    foreach(name ${ARGN})
        if("${name}" MATCHES "^(LIB|EXE|JAR)$")
            set(LAST_MODE "${name}")
        else("${name}" MATCHES "^(LIB|EXE|JAR)$")
            if("${LAST_MODE}" STREQUAL "LIB")
                if(WIN32)
                    set_target_properties(${ARGV0} PROPERTIES COMPILE_PDB_NAME "${name}")
                    set(LIBFILES_TO_COPY
                        ${LIBFILES_TO_COPY}
                        ${YBUILD_FULL_ARCHIVE_OUTPUT_DIRECTORY}/${name}.lib
                        ${YBUILD_FULL_ARCHIVE_OUTPUT_DIRECTORY}/${name}.pdb
                        )
                elseif(UNIX)
                    set(LIBFILES_TO_COPY
                        ${LIBFILES_TO_COPY}
                        ${YBUILD_FULL_ARCHIVE_OUTPUT_DIRECTORY}/lib${name}.a
                        )
                endif(WIN32)
            elseif("${LAST_MODE}" STREQUAL "JAR")
                set(LIBFILES_TO_COPY ${LIBFILES_TO_COPY} ${name})
            elseif("${LAST_MODE}" STREQUAL "EXE")
                if(WIN32)
                    set(EXEFILES_TO_COPY
                        ${EXEFILES_TO_COPY}
                        ${YBUILD_FULL_ARCHIVE_OUTPUT_DIRECTORY}/${name}.exe
                        )
                elseif(UNIX)
                    set(EXEFILES_TO_COPY
                        ${EXEFILES_TO_COPY}
                        ${YBUILD_FULL_ARCHIVE_OUTPUT_DIRECTORY}/${name}
                        )
                endif(WIN32)
            else("${LAST_MODE}" STREQUAL "LIB")
                message(FATAL_ERROR "Unknown or unspecified YBUILD_INSTALL_3RDPARTY mode [${LAST_MODE}]")
            endif("${LAST_MODE}" STREQUAL "LIB")
        endif("${name}" MATCHES "^(LIB|EXE|JAR)$")
    endforeach(name)

    if(DEFINED LIBFILES_TO_COPY)
        add_custom_command(
            TARGET ${target}
            POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${YBUILD_3RDPARTY_LIBRARY_DIR}/${tpdirname}"
            )

        foreach(f ${LIBFILES_TO_COPY})
            add_custom_command(
                TARGET ${target}
                POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy "${f}" "${YBUILD_3RDPARTY_LIBRARY_DIR}/${tpdirname}"
                )
        endforeach(f)
    endif(DEFINED LIBFILES_TO_COPY)
    
    if(DEFINED EXEFILES_TO_COPY)
        add_custom_command(
            TARGET ${target}
            POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory "${YBUILD_3RDPARTY_BINARY_DIR}/${tpdirname}"
            )

        foreach(f ${EXEFILES_TO_COPY})
            add_custom_command(
                TARGET ${target}
                POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy "${f}" "${YBUILD_3RDPARTY_BINARY_DIR}/${tpdirname}"
                )
        endforeach(f)
    endif(DEFINED EXEFILES_TO_COPY)
endfunction(YBUILD_INSTALL_3RDPARTY)

################################################
# YBUILD_CONFIGURE_BUILD
macro(YBUILD_CONFIGURE_BUILD)
    set(YBUILD_BASE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/_bin")

    if(MSVC_IDE)
        set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${YBUILD_BASE_RUNTIME_OUTPUT_DIRECTORY}")
        set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${YBUILD_BASE_RUNTIME_OUTPUT_DIRECTORY}")
        set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${YBUILD_BASE_RUNTIME_OUTPUT_DIRECTORY}")

        set(YBUILD_CFG_NAME "\$\(ConfigurationName\)")

        set(YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${YBUILD_CFG_NAME}")
        set(YBUILD_FULL_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/${YBUILD_CFG_NAME}")
        set(YBUILD_FULL_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/${YBUILD_CFG_NAME}")
    else(MSVC_IDE)
        set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${YBUILD_BASE_RUNTIME_OUTPUT_DIRECTORY}/${CMAKE_BUILD_TYPE}")
        set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${YBUILD_BASE_RUNTIME_OUTPUT_DIRECTORY}/${CMAKE_BUILD_TYPE}")
        set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${YBUILD_BASE_RUNTIME_OUTPUT_DIRECTORY}/${CMAKE_BUILD_TYPE}")

        set(YBUILD_CFG_NAME "${CMAKE_BUILD_TYPE}")

        set(YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}")
        set(YBUILD_FULL_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}")
        set(YBUILD_FULL_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
    endif(MSVC_IDE)

    set(YBUILD_3RDPARTY_BINARY_DIR "${CMAKE_SOURCE_DIR}/3rdparty/_bin/${YBUILD_CFG_NAME}")
    set(YBUILD_3RDPARTY_LIBRARY_DIR "${CMAKE_SOURCE_DIR}/3rdparty/_lib/${YBUILD_CFG_NAME}")

    ###########################################
    # Определим текущее состояние проекта в системе контроля версий.
    YBUILD_GET_VERSION_INFO()

    ###########################################
    # Установим общие настройки компиляции
    YBUILD_SET_COMMON_COMPILE_FLAGS()

    ###########################################
    # Подключим каталоги с заголовочными и библиотечными файлами
    YBUILD_ADD_3RDPARTY_DIRECTORIES()

    if(NOT DEFINED YBUILD_ENABLE_COM_REGISTRATION)
        set(YBUILD_ENABLE_COM_REGISTRATION 1)
    endif(NOT DEFINED YBUILD_ENABLE_COM_REGISTRATION)

    if(NOT DEFINED YBUILD_LANGUAGE)
        set(YBUILD_LANGUAGE ru_RU CACHE STRING "Yazyk" FORCE)
    endif(NOT DEFINED YBUILD_LANGUAGE)

    #get_cmake_property(VARS VARIABLES)
    #message("${VARS}")
    #foreach(var ${VARS})
    #    message("${var}=${${var}}")
    #endforeach(var)
endmacro(YBUILD_CONFIGURE_BUILD)

macro(YBUILD_ADD_FORCE_INCLUDE_FILES)
    YBUILD_FORCE_INCLUDE_FILE("${CMAKE_BINARY_DIR}/ConfigurationCommon.h")
    
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${FORCE_INCLUDES}" )
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${FORCE_INCLUDES}")
endmacro(YBUILD_ADD_FORCE_INCLUDE_FILES)


################################################
# YBUILD_FIND_MSBUILD
macro(YBUILD_FIND_MSBUILD)
    if(MSVC_VERSION GREATER_EQUAL 1911)
        set(MSBUILD_PROGRAM "$ENV{MSBUILD_PATH}")
        MARK_AS_ADVANCED(MSBUILD_PROGRAM)
    elseif(MSVC_VERSION EQUAL 1900)
        FIND_PROGRAM(MSBUILD_PROGRAM
            NAMES MSBuild
            PATHS
            [HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\MSBuild\\ToolsVersions\\14.0;MSBuildToolsPath]
            NO_DEFAULT_PATH
            )
        MARK_AS_ADVANCED(MSBUILD_PROGRAM)
    elseif(MSVC_VERSION EQUAL 1800)
        FIND_PROGRAM(MSBUILD_PROGRAM
            NAMES MSBuild
            PATHS
            [HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\MSBuild\\ToolsVersions\\12.0;MSBuildToolsPath]
            NO_DEFAULT_PATH
            )
        MARK_AS_ADVANCED(MSBUILD_PROGRAM)
    elseif(MSVC_VERSION EQUAL 1600)
        FILE(GLOB FRAMEWORKS "$ENV{windir}/Microsoft.NET/Framework/v4.0.*")
        LIST(SORT FRAMEWORKS)
        LIST(REVERSE FRAMEWORKS)
        FIND_PROGRAM(MSBUILD_PROGRAM
            NAMES MSBuild
            PATHS
            ${FRAMEWORKS}
            NO_DEFAULT_PATH
            )
        MARK_AS_ADVANCED(MSBUILD_PROGRAM)
    elseif(MSVC_VERSION EQUAL 1500)
        FIND_PROGRAM(MSBUILD_PROGRAM
            NAMES MSBuild
            PATHS
            "$ENV{windir}/Microsoft.NET/Framework/v3.5"
            NO_DEFAULT_PATH
            )
        MARK_AS_ADVANCED(MSBUILD_PROGRAM)
    else(MSVC_VERSION EQUAL 1600)
        FIND_PROGRAM(MSBUILD_PROGRAM
            NAMES MSBuild
            PATHS
            [HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\VisualStudio\\8.0\\MSBuild;MSBuildBinPath]
            "$ENV{windir}/Microsoft.NET/Framework/v2.0.50727"
            NO_DEFAULT_PATH
            )
        MARK_AS_ADVANCED(MSBUILD_PROGRAM)
    endif(MSVC_VERSION EQUAL 1800)
endmacro(YBUILD_FIND_MSBUILD)

macro(YBUILD_FIND_PROTOC)
    YBUILD_GET_TPLIB_DIR(protocdir protobuf)
    message("protobuf -- ${protocdir}")
    find_program(PROTOC_PROGRAM
        NAMES protoc protoc.exe
        PATHS
            "${CMAKE_SOURCE_DIR}/3rdparty/_bin/Release/${protocdir}"
        )
    mark_as_advanced(PROTOC_PROGRAM)
endmacro(YBUILD_FIND_PROTOC)

################################################
# YBUILD_PREPARE_SRC_LIST
function(YBUILD_PREPARE_SRC_LIST pchname srclist)
    set(MYSRCLIST "${${srclist}}")
    set(PCHNAMES stdpch stdafx)
    set(PCH_FOUND FALSE)
    foreach(cname ${PCHNAMES})
        file(GLOB FULL_PCHNAME_T ${cname}.cpp)
        if(FULL_PCHNAME_T)
            list(FIND MYSRCLIST ${FULL_PCHNAME_T} PCH_INDEX)
            if(PCH_INDEX EQUAL -1)
            else(PCH_INDEX EQUAL -1)
                set(PCH_FOUND TRUE)
                get_filename_component(PCH_NAME "${FULL_PCHNAME_T}" NAME_WE)
                set(${pchname} "${PCH_NAME}" PARENT_SCOPE)
                set(FULL_PCHNAME ${FULL_PCHNAME_T})
                break()
            endif(PCH_INDEX EQUAL -1)
        endif(FULL_PCHNAME_T)
    endforeach(cname)

    if(PCH_FOUND)
        YBUILD_EXCLUDE_FILES(MYSRCLIST ${PCH_NAME}.cpp)
        set(${srclist} ${FULL_PCHNAME} ${MYSRCLIST} PARENT_SCOPE)
    endif(PCH_FOUND)
endfunction(YBUILD_PREPARE_SRC_LIST)

################################################
# YBUILD_GENERATE_PROJECT_TREE
function(YBUILD_GENERATE_PROJECT_TREE ProjectDir ProjectSources)
    if(ARGC GREATER 2)
        set(Prefix "${ARGV2}")
    endif(ARGC GREATER 2)

    set(DirSources "${ProjectSources}") 
    foreach(Source ${DirSources})
        string(REGEX REPLACE "${ProjectDir}" "" RelativePath "${Source}")
        string(REGEX REPLACE "${CMAKE_CURRENT_BINARY_DIR}" "" RelativePath "${RelativePath}")
        string(REGEX REPLACE "[\\\\/][^\\\\/]*$" "" RelativePath "${RelativePath}")
        string(REGEX REPLACE "^[\\\\/]" "" RelativePath "${RelativePath}")
        string(REGEX REPLACE "/" "\\\\\\\\" RelativePath "${RelativePath}")
        source_group("${Prefix}${RelativePath}" FILES ${Source})
    endforeach(Source)
endfunction(YBUILD_GENERATE_PROJECT_TREE)

################################################
# YBUILD_ADD_STANDARD_PROJECT
function(YBUILD_ADD_STANDARD_PROJECT name type)
    set(CPP_PROJECT_TYPES "^(EXE|WINEXE|LIB|DLL)$")
    set(CS_PROJECT_TYPES "^(CSEXE|CSDLL|ANDLL|ANDR)$")
    set(CPPCLI_PROJECT_TYPES "^(MDLL)$")
    set(MSBUILD_PROJECT_TYPES "^(CSEXE|CSDLL|MDLL|ANDR|ANDLL)$")
    set(SUBCOMMAND_ARGS "^(SOURCES|ADDITIONAL_SOURCES|GENERATE_PROXY_STUB|NO_PRECOMPILED_HEADER|MANAGED_INTEROP_NAMESPACE|MANAGED_PLATFORM|ADDITIONAL_MSBUILD_PROPERTIES|TARGET_BINARY_NAME|PROTO_PATH|RUN_EVERY_TIME)$")
    
    set(GENERATE_PROXY_STUB FALSE)
    set(PRECOMPILED_HEADER TRUE)
    set(RUN_EVERY_TIME "")
    set(ARGMODE UNKNOWN)
    
    set(MANAGED_INTEROP_NAMESPACE_NAME "${name}")
    set(PROJECT_MANAGED_PLATFORM "UNDEFINED")
    set(ADDIT_MSBUILD_CFG)
    
    set(TGT_BINARY_NAME "${name}")
    set(PBUF_INCLUDES)
    
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/VersionInfo.Generated.rc.in")
        configure_file("${CMAKE_CURRENT_SOURCE_DIR}/VersionInfo.Generated.rc.in" "${CMAKE_CURRENT_SOURCE_DIR}/VersionInfo.Generated.rc")
    endif()

    if("${type}" MATCHES "${CPPCLI_PROJECT_TYPES}")
        if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/AssemblyVersionInfo.Generated.cpp.in")
            configure_file("${CMAKE_CURRENT_SOURCE_DIR}/AssemblyVersionInfo.Generated.cpp.in" "${CMAKE_CURRENT_SOURCE_DIR}/AssemblyVersionInfo.Generated.cpp")
        endif()
    endif()
    
    foreach(arg ${ARGN})
        if("${arg}" MATCHES "${SUBCOMMAND_ARGS}")
            set(ARGMODE UNKNOWN)
            set(GLOBMODE NONREC)
            
            if("${arg}" STREQUAL "GENERATE_PROXY_STUB")
                set(GENERATE_PROXY_STUB TRUE)
            elseif("${arg}" STREQUAL "NO_PRECOMPILED_HEADER")
                set(PRECOMPILED_HEADER FALSE)
            elseif("${arg}" STREQUAL "RUN_EVERY_TIME")
                set(RUN_EVERY_TIME "ALL")
            else()
                set(ARGMODE "${arg}")
            endif()
        else()
            set(SIMPLE_ARGMODE ${ARGMODE})
            if("${ARGMODE}" STREQUAL "SOURCES")
                set(TARGETVAR PRJSOURCES)
            elseif("${ARGMODE}" STREQUAL "ADDITIONAL_SOURCES")
                set(TARGETVAR ADDITIONAL_PRJSOURCES)
                set(SIMPLE_ARGMODE "SOURCES")
            endif()
            
            if("${SIMPLE_ARGMODE}" STREQUAL "SOURCES")
                if("${arg}" STREQUAL "GLOB")
                    set(GLOBMODE NONREC)
                elseif("${arg}" STREQUAL "GLOB_RECURSE")
                    set(GLOBMODE REC)
                elseif("${arg}" STREQUAL "NOGLOB")
                    set(GLOBMODE FALSE)
                else("${arg}" STREQUAL "GLOB")
                    if(GLOBMODE)
                        if("${GLOBMODE}" STREQUAL "REC")
                            file(GLOB_RECURSE PRJSOURCE_GLOB "${arg}")
                        elseif("${GLOBMODE}" STREQUAL "NONREC")
                            file(GLOB PRJSOURCE_GLOB "${arg}")
                        endif("${GLOBMODE}" STREQUAL "REC")
                        list(APPEND ${TARGETVAR} ${PRJSOURCE_GLOB})
                    else()
                        set(${TARGETVAR} "${${TARGETVAR}}" "${arg}")
                    endif()
                endif()
            elseif("${SIMPLE_ARGMODE}" STREQUAL "MANAGED_INTEROP_NAMESPACE")
                set(MANAGED_INTEROP_NAMESPACE_NAME "${arg}")
                set(ARGMODE UNKNOWN)
            elseif("${SIMPLE_ARGMODE}" STREQUAL "MANAGED_PLATFORM")
                set(PROJECT_MANAGED_PLATFORM "${arg}")
                set(ARGMODE UNKNOWN)
            elseif("${SIMPLE_ARGMODE}" STREQUAL "ADDITIONAL_MSBUILD_PROPERTIES")
                set(ADDIT_MSBUILD_CFG "${arg}")
                set(ARGMODE UNKNOWN)
            elseif("${SIMPLE_ARGMODE}" STREQUAL "TARGET_BINARY_NAME")
                set(TGT_BINARY_NAME "${arg}")
                set(ARGMODE UNKNOWN)
            elseif("${SIMPLE_ARGMODE}" STREQUAL "PROTO_PATH")
                set(PBUF_INCLUDES "${PBUF_INCLUDES}" "${arg}")
            else()
                message(FATAL_ERROR "Unexpected YBUILD_ADD_STANDARD_PROJECT argument: ${arg}")
            endif()
        endif()
    endforeach(arg)
    
    if(NOT DEFINED PRJSOURCES)
        if("${type}" MATCHES "${CPP_PROJECT_TYPES}")
            file(GLOB_RECURSE PRJSOURCES *.cpp *.h *.c *.cxx *.hpp *.rgs *.rc *.proto)
        elseif("${type}" MATCHES "${CPPCLI_PROJECT_TYPES}")
            file(GLOB_RECURSE PRJSOURCES *.cpp *.h *.c *.cxx *.hpp *.rgs *.rc)
        elseif("${type}" MATCHES "${CS_PROJECT_TYPES}")
            file(GLOB_RECURSE PRJSOURCES *.cs *.resx *.bmp *.png *.csproj *.jpg)
        endif()
    endif()

    foreach(src ${ADDITIONAL_PRJSOURCES})
        list(FIND PRJSOURCES "${src}" SRC_INDEX)
        if(SRC_INDEX EQUAL -1)
            set(PRJSOURCES "${PRJSOURCES}" "${src}")
        endif()
    endforeach(src)
    
    set(PRJ_PROTO_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}")
    set(PRJ_HAVEPROTO FALSE)
    set(PRJ_PROTO_LIST)
    set(PROTOC_GENERATED_FILES)
    
    if("${type}" MATCHES "${CPP_PROJECT_TYPES}")
        YBUILD_PREPARE_SRC_LIST(PRJPCHNAME PRJSOURCES)
        
        foreach(src ${PRJSOURCES})
            get_filename_component(PRJSRC_EXT "${src}" EXT)
            if("${PRJSRC_EXT}" STREQUAL ".proto")
                set(PRJ_HAVEPROTO TRUE)
                set(PRJ_PROTO_LIST "${PRJ_PROTO_LIST}" "${src}")
                get_filename_component(PROTO_NAME "${src}" NAME_WE)
                set(PROTO_GFILES "${PRJ_PROTO_TARGET_DIR}/${PROTO_NAME}.pb.h" "${PRJ_PROTO_TARGET_DIR}/${PROTO_NAME}.pb.cc")
                set(GENERATED_PRJSOURCES "${GENERATED_PRJSOURCES}" "${PROTO_GFILES}")
                set(PROTOC_GENERATED_FILES "${PROTOC_GENERATED_FILES}" "${PROTO_GFILES}")

                get_source_file_property(CPROPERTIES "${PRJ_PROTO_TARGET_DIR}/${PROTO_NAME}.pb.cc" COMPILE_FLAGS)
                
                if(NOT CPROPERTIES)
                    if(WIN32)
                        set(CPROPERTIES "/Y- ")
                    else()
                        set(CPROPERTIES " ")
                    endif()
                else()
                    set(CPROPERTIES "/Y- ${CPROPERTIES}")
                endif()

                set_source_files_properties("${PRJ_PROTO_TARGET_DIR}/${PROTO_NAME}.pb.cc" PROPERTIES COMPILE_FLAGS "${CPROPERTIES}")
            endif()
        endforeach(src)
        
        if(PRJ_HAVEPROTO)
            set(PRJ_PROTO_OUTDIR)
            foreach(pincl ${PBUF_INCLUDES})
                set(PRJ_PROTO_INCLUDE_DIRS "${PRJ_PROTO_INCLUDE_DIRS}" "-I${pincl}")
            endforeach(pincl)
        endif()
    endif()

    foreach(src ${GENERATED_PRJSOURCES})
        list(FIND PRJSOURCES "${src}" SRC_INDEX)
        if(SRC_INDEX EQUAL -1)
            set(PRJSOURCES "${PRJSOURCES}" "${src}")
        endif()
    endforeach(src)
    
    if(PRJ_HAVEPROTO)
        include_directories("${PRJ_PROTO_TARGET_DIR}")
        add_custom_command(
            OUTPUT "${PRJ_PROTO_TARGET_DIR}/dummy_protobuf.dependency"
            COMMAND ${CMAKE_COMMAND} -E make_directory "${PRJ_PROTO_TARGET_DIR}"
            COMMAND ${CMAKE_COMMAND} -E touch "${PRJ_PROTO_TARGET_DIR}/dummy_protobuf.dependency"
            VERBATIM
            )
            
        add_custom_command(
            OUTPUT ${PROTOC_GENERATED_FILES}
            DEPENDS ${PRJ_PROTO_LIST} "${PRJ_PROTO_TARGET_DIR}/dummy_protobuf.dependency"
            COMMAND "${PROTOC_PROGRAM}" ${PRJ_PROTO_LIST} ${PRJ_PROTO_INCLUDE_DIRS} --cpp_out=${PRJ_PROTO_TARGET_DIR}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            VERBATIM
            )
    endif()

    if("${type}" STREQUAL "EXE")
        add_executable(${name} ${PRJSOURCES})
	if("${USE_VS13_NMAKE_XP_HACK}" EQUAL 1)
            set_target_properties(${name} PROPERTIES LINK_FLAGS "/SUBSYSTEM:CONSOLE,5.01")
    	endif()
    elseif("${type}" STREQUAL "WINEXE")
        add_executable(${name} WIN32 ${PRJSOURCES})
    elseif("${type}" STREQUAL "LIB")
        add_library(${name} STATIC ${PRJSOURCES})
    elseif("${type}" STREQUAL "DLL")
        add_library(${name} SHARED ${PRJSOURCES})
	if("${USE_VS13_NMAKE_XP_HACK}" EQUAL 1)
            set_target_properties(${name} PROPERTIES LINK_FLAGS "/SUBSYSTEM:CONSOLE,5.01")
    	endif()
    elseif("${type}" MATCHES "${MSBUILD_PROJECT_TYPES}")
        file(TO_NATIVE_PATH ${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY} CSPROJ_OUTDIR)
        
        if("${type}" MATCHES "${CS_PROJECT_TYPES}")
            if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/Properties/AssemblyVersionInfo.Generated.cs.in")
                configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Properties/AssemblyVersionInfo.Generated.cs.in" "${CMAKE_CURRENT_SOURCE_DIR}/Properties/AssemblyVersionInfo.Generated.cs")
            endif()
        endif()

        if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/Properties/AndroidManifest.xml.in")
            configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Properties/AndroidManifest.xml.in" "${CMAKE_CURRENT_SOURCE_DIR}/Properties/AndroidManifest.xml")
        endif()
        
        if("${type}" STREQUAL "CSEXE")
            set(TARGET_EXT exe)
        elseif("${type}" STREQUAL "CSDLL")
            set(TARGET_EXT dll)
        elseif("${type}" STREQUAL "MDLL")
            set(TARGET_EXT dll)
        elseif("${type}" STREQUAL "ANDLL")
            set(TARGET_EXT dll)
        elseif("${type}" STREQUAL "ANDR")
            set(TARGET_EXT apk)
        endif("${type}" STREQUAL "CSEXE")
        
        if("${type}" STREQUAL "ANDR")
            if("${YBUILD_CFG_NAME}" STREQUAL "Release")
                set(TARGET_BUILD SignAndroidPackage)
                set(ANDROID_KEYSTORE "AndroidKeyStore=True\;AndroidSigningKeyStore=${CMAKE_CURRENT_SOURCE_DIR}/../install/${TGT_BINARY_NAME}.keystore\;AndroidSigningStorePass=123456\;AndroidSigningKeyAlias=yunker\;AndroidSigningKeyPass=123456")
            else()
                set(TARGET_BUILD Package)
            endif()
        else()
            set(TARGET_BUILD Build)
        endif()
        
        if("${PROJECT_MANAGED_PLATFORM}" STREQUAL "UNDEFINED")
            set(PROJECT_MANAGED_PLATFORM "x86")
        endif()
        
        if("${type}" MATCHES "${CS_PROJECT_TYPES}")
            set(PROJECT_EXT csproj)
        else()
            set(PROJECT_EXT ${YBUILD_EXTENSION_FOR_MANAGED_PROJECTS})
        endif()
        
        add_custom_target(${name} ${RUN_EVERY_TIME}
            DEPENDS ${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${TGT_BINARY_NAME}.${TARGET_EXT} ${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${TGT_BINARY_NAME}.pdb
            SOURCES ${PRJSOURCES}
            )
        
        if("${type}" STREQUAL "ANDR" OR "${type}" STREQUAL "ANDLL")
            set(MSBUILD_PROPERTIES "Configuration=${YBUILD_CFG_NAME}\;OutputPath=${CSPROJ_OUTDIR}\;YCmake=CMake\;YBrandName=${CMAKE_BRAND_NAME}\;AndroidSdkDirectory=${YBUILD_TPLIB_ANDROID-SDK_PATH}/")
        else()
            set(MSBUILD_PROPERTIES "Configuration=${YBUILD_CFG_NAME}\;Platform=${PROJECT_MANAGED_PLATFORM}\;OutputPath=${CSPROJ_OUTDIR}\;YBrandName=${CMAKE_BRAND_NAME}\;YCmake=CMake")
        endif()
        
        if(ANDROID_KEYSTORE)
            set(MSBUILD_PROPERTIES "${ANDROID_KEYSTORE}\;${MSBUILD_PROPERTIES}")
        endif()

        if(ADDIT_MSBUILD_CFG)
            set(MSBUILD_PROPERTIES "${ADDIT_MSBUILD_CFG}\;${MSBUILD_PROPERTIES}")
        endif()
        
        if("${type}" MATCHES "${CS_PROJECT_TYPES}")
            set(MSBUILD_PROPERTIES "${MSBUILD_PROPERTIES}\;YBuildRoot=${CMAKE_SOURCE_DIR}")
        endif()
        if("${type}" MATCHES "${CPPCLI_PROJECT_TYPES}")
            get_directory_property(CPLDEFS COMPILE_DEFINITIONS)
            set(DEFLIST)
            foreach(def ${CPLDEFS})
                if("${DEFLIST}" STREQUAL "")
                    set(DEFLIST "${def}")
                else()
                    set(DEFLIST "${DEFLIST}\;${def}")
                endif()
            endforeach(def)
            set(MSBUILD_PROPERTIES "${MSBUILD_PROPERTIES}\;YBuildPreprocessorDefinitions=\"${DEFLIST}\"")
            
            get_directory_property(INCLDIRS INCLUDE_DIRECTORIES)
            set(INCLIST)
            foreach(incl ${INCLDIRS})
                if("${INCLIST}" STREQUAL "")
                    set(INCLIST "${incl}")
                else()
                    set(INCLIST "${INCLIST}\;${incl}")
                endif()
            endforeach(incl)
            set(MSBUILD_PROPERTIES "${MSBUILD_PROPERTIES}\;YBuildAdditionalIncludeDirectories=\"${INCLIST}\"")

            get_directory_property(LINKDIRS LINK_DIRECTORIES)
            set(LINKLIST)
            foreach(link ${LINKDIRS})
                if("${LINKLIST}" STREQUAL "")
                    set(LINKLIST "${link}")
                else()
                    set(LINKLIST "${LINKLIST}\;${link}")
                endif()
            endforeach(link)
            set(MSBUILD_PROPERTIES "${MSBUILD_PROPERTIES}\;YBuildAdditionalLibraryDirectories=\"${LINKLIST}\"")
        endif()

        add_custom_command(
            OUTPUT ${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${TGT_BINARY_NAME}.${TARGET_EXT} ${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${TGT_BINARY_NAME}.pdb
            COMMAND SET LIB=
            COMMAND SET YBuildAdditionalIncludeDirectories2=${YBuildAdditionalIncludeDirectories2}
            COMMAND ${MSBUILD_PROGRAM}
                ${name}.${PROJECT_EXT}
                /v:q
                /nologo
                /t:${TARGET_BUILD}
                /p:${MSBUILD_PROPERTIES}
            DEPENDS ${PRJSOURCES}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            )
    else()
        message(FATAL_ERROR "Unknown project type [${type}] specified for YBUILD_ADD_STANDARD_PROJECT")
    endif()

    YBUILD_GENERATE_PROJECT_TREE(${CMAKE_CURRENT_SOURCE_DIR} "${PRJSOURCES}")
    
    if(MSVC AND DEFINED PRJPCHNAME AND PRECOMPILED_HEADER)
        set_source_files_properties(${PRJPCHNAME}.cpp PROPERTIES COMPILE_FLAGS "/Yc${PRJPCHNAME}.h")
        set_target_properties(${name} PROPERTIES COMPILE_FLAGS "/Yu${PRJPCHNAME}.h")
    endif()
endfunction(YBUILD_ADD_STANDARD_PROJECT)

################################################
# YBUILD_REGISTER_COM_OBJECT
function(YBUILD_REGISTER_COM_OBJECT target)
    if(WIN32 AND YBUILD_ENABLE_COM_REGISTRATION)
        file(TO_NATIVE_PATH "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${target}.dll" TARGET_NATIVE_DLL_PATH)
        add_custom_command(
            TARGET ${target}
            POST_BUILD
            COMMAND regsvr32 /s \"${TARGET_NATIVE_DLL_PATH}\"
            )
    endif(WIN32 AND YBUILD_ENABLE_COM_REGISTRATION)
endfunction(YBUILD_REGISTER_COM_OBJECT)

################################################
# YBUILD_LINK_ADV601
function(YBUILD_LINK_ADV601 target)
    set(ADV601_SRC_DLL "${YBUILD_TPLIB_AMWSDK_PATH}/lib/AW_ADV601Lib.dll")
    set(ADV601_DST_DLL "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/AW_ADV601Lib.dll")

    target_link_libraries(${target} AW_ADV601Lib)

    get_property(ADV601_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_ADV601_COPY_ACTION_REGISTERED)
    if(NOT ADV601_ALREADY_REGISTERED)
        add_custom_target(
            Adv601Copy
            DEPENDS "${ADV601_DST_DLL}"
            )
        add_custom_command(
            OUTPUT "${ADV601_DST_DLL}"
            COMMAND ${CMAKE_COMMAND} -E copy "${ADV601_SRC_DLL}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
            MAIN_DEPENDENCY "${ADV601_SRC_DLL}"
            VERBATIM
            )
        set_property(GLOBAL PROPERTY YBUILD_ADV601_COPY_ACTION_REGISTERED ON)
    endif(NOT ADV601_ALREADY_REGISTERED)
    add_dependencies(${target} Adv601Copy)
endfunction(YBUILD_LINK_ADV601)

################################################
# YBUILD_LINK_AMPFFT
function(YBUILD_LINK_AMPFFT target)
    set(AMPFFT_DLLS "d3dcsx_47.dll")

    get_property(AMPFFT_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_AMPFFT_COPY_ACTION_REGISTERED)
    if(NOT AMPFFT_ALREADY_REGISTERED)
        set(AMPFFT_DST_DLLS)

        foreach(dll ${AMPFFT_DLLS})
            set(AMPFFT_DST_DLLS ${AMPFFT_DST_DLLS} "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}")
        endforeach(dll)

        add_custom_target(
            ampfftcopy
            DEPENDS ${AMPFFT_DST_DLLS}
            )
        foreach(dll ${AMPFFT_DLLS})
            add_custom_command(
                OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                COMMAND ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_AMP-FFT_PATH}/bin/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                MAIN_DEPENDENCY "${YBUILD_TPLIB_AMP-FFT_PATH}/bin/${dll}"
                VERBATIM
                )
        endforeach(dll)
        set_property(GLOBAL PROPERTY YBUILD_AMPFFT_COPY_ACTION_REGISTERED ON)
    endif(NOT AMPFFT_ALREADY_REGISTERED)
    add_dependencies(${target} ampfftcopy)
endfunction(YBUILD_LINK_AMPFFT)

################################################
# YBUILD_LINK_FFMPEG1 v.23.05.2013
function(YBUILD_LINK_FFMPEG1 target)
    set(FFMPEG_DLLS "avcodec-55.dll" "avfilter-3.dll" "avformat-55.dll" "avutil-52.dll" "swscale-2.dll" "postproc-52.dll" "swresample-0.dll")
    YBUILD_LINK_FFMPEG(${target})
endfunction(YBUILD_LINK_FFMPEG1)

################################################
# YBUILD_LINK_FFMPEG2 v.11.06.2015
function(YBUILD_LINK_FFMPEG2 target)
    set(FFMPEG_DLLS "avcodec-56.dll" "avfilter-5.dll" "avformat-56.dll" "avutil-54.dll" "swscale-3.dll" "postproc-53.dll" "swresample-1.dll")
    YBUILD_LINK_FFMPEG(${target})
endfunction(YBUILD_LINK_FFMPEG2)

################################################
# YBUILD_LINK_FFMPEG4 v.4.0.1
function(YBUILD_LINK_FFMPEG4 target)
    set(FFMPEG_DLLS "avcodec-58.dll" "avfilter-7.dll" "avformat-58.dll" "avutil-56.dll" "swscale-5.dll" "postproc-55.dll" "swresample-3.dll")
    YBUILD_LINK_FFMPEG(${target})
endfunction(YBUILD_LINK_FFMPEG4)

################################################
# YBUILD_LINK_FFMPEG
function(YBUILD_LINK_FFMPEG target)
    get_property(FFMPEG_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_FFMPEG_COPY_ACTION_REGISTERED)
    if(NOT FFMPEG_ALREADY_REGISTERED)
        set(FFMPEG_DST_DLLS)

        foreach(dll ${FFMPEG_DLLS})
            set(FFMPEG_DST_DLLS ${FFMPEG_DST_DLLS} "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}")
        endforeach(dll)

        add_custom_target(
            ffmpegpcopy
            DEPENDS ${FFMPEG_DST_DLLS}
            )
        foreach(dll ${FFMPEG_DLLS})
            add_custom_command(
                OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                COMMAND ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_FFMPEG_PATH}/bin/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                MAIN_DEPENDENCY "${YBUILD_TPLIB_FFMPEG_PATH}/bin/${dll}"
                VERBATIM
                )
        endforeach(dll)
        set_property(GLOBAL PROPERTY YBUILD_FFMPEG_COPY_ACTION_REGISTERED ON)
    endif(NOT FFMPEG_ALREADY_REGISTERED)
    add_dependencies(${target} ffmpegpcopy)
endfunction(YBUILD_LINK_FFMPEG)

################################################
# YBUILD_LINK_IPP
function(YBUILD_LINK_IPP target)
    set(IPP_DLLS "ippcore.dll" "ippcc.dll" "ippccg9.dll" "ippcch9.dll" "ippccp8.dll" "ippccs8.dll" "ippccw7.dll" "ippch.dll" "ippchg9.dll" "ippchh9.dll" "ippchp8.dll" "ippchs8.dll" "ippchw7.dll" "ippcore.dll" "ippcv.dll"
        "ippcvg9.dll" "ippcvh9.dll" "ippcvp8.dll" "ippcvs8.dll" "ippcvw7.dll" "ippdc.dll" "ippdcg9.dll" "ippdch9.dll" "ippdcp8.dll" "ippdcs8.dll" "ippdcw7.dll" "ippi.dll" "ippig9.dll" "ippih9.dll" "ippip8.dll"
        "ippis8.dll" "ippiw7.dll" "ipps.dll" "ippsg9.dll" "ippsh9.dll" "ippsp8.dll" "ippss8.dll" "ippsw7.dll" "ippvm.dll" "ippvmg9.dll" "ippvmh9.dll" "ippvmp8.dll" "ippvms8.dll" "ippvmw7.dll")
    
    get_property(IPP_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_IPP_COPY_ACTION_REGISTERED)
    if(NOT IPP_ALREADY_REGISTERED)
        set(IPP_DST_DLLS)

        foreach(dll ${IPP_DLLS})
            set(IPP_DST_DLLS ${IPP_DST_DLLS} "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}")
        endforeach(dll)

        add_custom_target(
            ippcopy
            DEPENDS ${IPP_DST_DLLS}
            )
        foreach(dll ${IPP_DLLS})
            add_custom_command(
                OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                COMMAND ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_IPP_PATH}/bin/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                MAIN_DEPENDENCY "${YBUILD_TPLIB_IPP_PATH}/bin/${dll}"
                VERBATIM
                )
        endforeach(dll)
        set_property(GLOBAL PROPERTY YBUILD_IPP_COPY_ACTION_REGISTERED ON)
    endif(NOT IPP_ALREADY_REGISTERED)
    add_dependencies(${target} ippcopy)
endfunction(YBUILD_LINK_IPP)

################################################
# YBUILD_LINK_IPP
function(YBUILD_LINK_BOOST_THREAD target)
    set(BOOST_DLLS_RELEASE "boost_system-vc141-mt-1_65.dll" "boost_thread-vc141-mt-1_65.dll" "boost_chrono-vc141-mt-1_65.dll")
    set(BOOST_DLLS_DEBUG "boost_system-vc141-mt-gd-1_65.dll" "boost_thread-vc141-mt-gd-1_65.dll" "boost_chrono-vc141-mt-gd-1_65.dll")
    
    get_property(BOOST_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_BOOST_COPY_ACTION_REGISTERED)
    if(NOT BOOST_ALREADY_REGISTERED)
        set(BOOST_DST_DLLS)
        set(BOOST_DLLS)

        if(MSVC_IDE OR "${YBUILD_CFG_NAME}" STREQUAL "Release")
            foreach(dll ${BOOST_DLLS_RELEASE})
                set(BOOST_DST_DLLS ${BOOST_DST_DLLS} "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}")
            endforeach(dll)
            set(BOOST_DLLS ${BOOST_DLLS_RELEASE})
        endif()

        if(MSVC_IDE OR "${YBUILD_CFG_NAME}" STREQUAL "Debug")
            foreach(dll ${BOOST_DLLS_DEBUG})
                set(BOOST_DST_DLLS ${BOOST_DST_DLLS} "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}")
            endforeach(dll)
            set(BOOST_DLLS ${BOOST_DLLS_DEBUG})
        endif()
        
        add_custom_target(
            boostthreadcopy
            DEPENDS ${BOOST_DST_DLLS}
            )
                
        if(MSVC_IDE)
            foreach(dll ${BOOST_DLLS_DEBUG})
                add_custom_command(
                    OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                    COMMAND if $(ConfigurationName) == Debug ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_BOOST_PATH}/stage/lib/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                    MAIN_DEPENDENCY "${YBUILD_TPLIB_BOOST_PATH}/stage/lib/${dll}"
                    VERBATIM
                    )
            endforeach(dll)
            
            foreach(dll ${BOOST_DLLS_RELEASE})
                add_custom_command(
                    OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                    COMMAND if $(ConfigurationName) == Release ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_BOOST_PATH}/stage/lib/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                    MAIN_DEPENDENCY "${YBUILD_TPLIB_BOOST_PATH}/stage/lib/${dll}"
                    VERBATIM
                    )
            endforeach(dll)        
        else()
            foreach(dll ${BOOST_DLLS})
                add_custom_command(
                    OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                    COMMAND ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_BOOST_PATH}/stage/lib/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                    MAIN_DEPENDENCY "${YBUILD_TPLIB_BOOST_PATH}/stage/lib/${dll}"
                    VERBATIM
                    )
            endforeach(dll)  
        endif()
       
        set_property(GLOBAL PROPERTY YBUILD_BOOST_COPY_ACTION_REGISTERED ON)
    endif()
    
    add_dependencies(${target} boostthreadcopy)
endfunction()

################################################
# YBUILD_LINK_IPP
function(YBUILD_LINK_FTD2XX target)
    set(FTD2XX_DLLS "ftd2xx.dll")
    
    get_property(FTD2XX_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_FTD2XX_COPY_ACTION_REGISTERED)
    if(NOT FTD2XX_ALREADY_REGISTERED)
        set(FTD2XX_DST_DLLS)

        foreach(dll ${FTD2XX_DLLS})
            set(FTD2XX_DST_DLLS ${FTD2XX_DST_DLLS} "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}")
        endforeach(dll)

        add_custom_target(
            ftd2xxcopy
            DEPENDS ${FTD2XX_DST_DLLS}
            )
        foreach(dll ${FTD2XX_DLLS})
            add_custom_command(
                OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                COMMAND ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_FTD2XX_PATH}/install/driver/CDM v2.12.10 WHQL Certified/i386/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                MAIN_DEPENDENCY "${YBUILD_TPLIB_FTD2XX_PATH}/install/driver/CDM v2.12.10 WHQL Certified/i386/${dll}"
                VERBATIM
                )
        endforeach(dll)
        set_property(GLOBAL PROPERTY YBUILD_FTD2XX_COPY_ACTION_REGISTERED ON)
    endif(NOT FTD2XX_ALREADY_REGISTERED)
    
    add_dependencies(${target} ftd2xxcopy)
endfunction(YBUILD_LINK_FTD2XX)

################################################
# YBUILD_LINK_HW_CODECS
function(YBUILD_LINK_HW_CODECS target)
    set(INTEL_HW_CODECS_DLLS "libmfxsw32.dll")

    get_property(HW_CODECS_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_HW_CODECS_COPY_ACTION_REGISTERED)
    if(NOT HW_CODECS_ALREADY_REGISTERED)
        set(HW_CODECS_DST_DLLS)

        foreach(dll ${INTEL_HW_CODECS_DLLS})
            set(HW_CODECS_DST_DLLS ${HW_CODECS_DST_DLLS} "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}")
        endforeach(dll)

        add_custom_target(
            hwcodecscopy
            DEPENDS ${HW_CODECS_DST_DLLS}
            )

        foreach(dll ${INTEL_HW_CODECS_DLLS})
            add_custom_command(
                OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                COMMAND ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_INTEL-MEDIA-SDK_PATH}/bin/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                MAIN_DEPENDENCY "${YBUILD_TPLIB_INTEL-MEDIA-SDK_PATH}/bin/${dll}"
                VERBATIM
                )
        endforeach(dll)
        set_property(GLOBAL PROPERTY YBUILD_HW_CODECS_COPY_ACTION_REGISTERED ON)
    endif(NOT HW_CODECS_ALREADY_REGISTERED)
    add_dependencies(${target} hwcodecscopy)
endfunction(YBUILD_LINK_HW_CODECS)

################################################
# YBUILD_LINK_W95SCM
function(YBUILD_LINK_W95SCM target)
    set(W95SCM_SRC_DLL "${YBUILD_TPLIB_WN95SCM_PATH}/lib/w95scm.dll")
    set(W95SCM_DST_DLL "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/w95scm.dll")

    target_link_libraries(${target} w95scm)

    get_property(W95SCM_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_W95SCM_COPY_ACTION_REGISTERED)
    if(NOT W95SCM_ALREADY_REGISTERED)
        add_custom_target(
            W95ScmCopy
            DEPENDS "${W95SCM_DST_DLL}"
            )
        add_custom_command(
            OUTPUT "${W95SCM_DST_DLL}"
            COMMAND ${CMAKE_COMMAND} -E copy "${W95SCM_SRC_DLL}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
            MAIN_DEPENDENCY "${W95SCM_SRC_DLL}"
            VERBATIM
            )
        set_property(GLOBAL PROPERTY YBUILD_W95SCM_COPY_ACTION_REGISTERED ON)
    endif(NOT W95SCM_ALREADY_REGISTERED)
    add_dependencies(${target} W95ScmCopy)
endfunction(YBUILD_LINK_W95SCM)

################################################
# YBUILD_LINK_NSP
function(YBUILD_LINK_NSP target)
    set(NSP_DLLS "cpuinf32.dll" "nsp.dll" "nspa6.dll" "nspm5.dll" "nspm6.dll" "nspp6.dll" "nsppx.dll")
        
    target_link_libraries(${target} nsp)

    get_property(NSP_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_NSP_COPY_ACTION_REGISTERED)
    if(NOT NSP_ALREADY_REGISTERED)
        set(NSP_DST_DLLS)
        
        foreach(dll ${NSP_DLLS})
            set(NSP_DST_DLLS ${NSP_DST_DLLS} "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}")
        endforeach(dll)
        
        add_custom_target(
            nspcopy
            DEPENDS ${NSP_DST_DLLS}
            )
        foreach(dll ${NSP_DLLS})
            add_custom_command(
                OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                COMMAND ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_NSP_PATH}/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                MAIN_DEPENDENCY "${YBUILD_TPLIB_NSP_PATH}/${dll}"
                VERBATIM
                )
        endforeach(dll)
        set_property(GLOBAL PROPERTY YBUILD_NSP_COPY_ACTION_REGISTERED ON)
    endif(NOT NSP_ALREADY_REGISTERED)
    add_dependencies(${target} nspcopy)
endfunction(YBUILD_LINK_NSP)

################################################
# YBUILD_LINK_BASS
function(YBUILD_LINK_BASS target)
    set(BASS_SRC_DLL "${YBUILD_TPLIB_BASS_PATH}/lib/bass.dll")
    set(BASS_DST_DLL "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/bass.dll")

    target_link_libraries(${target} bass)

    get_property(BASS_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_BASS_COPY_ACTION_REGISTERED)
    if(NOT BASS_ALREADY_REGISTERED)
        add_custom_target(
            BassCopy
            DEPENDS "${BASS_DST_DLL}"
            )
        add_custom_command(
            OUTPUT "${BASS_DST_DLL}"
            COMMAND ${CMAKE_COMMAND} -E copy "${BASS_SRC_DLL}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
            MAIN_DEPENDENCY "${BASS_SRC_DLL}"
            VERBATIM
            )
        set_property(GLOBAL PROPERTY YBUILD_BASS_COPY_ACTION_REGISTERED ON)
    endif(NOT BASS_ALREADY_REGISTERED)
    add_dependencies(${target} BassCopy)
endfunction(YBUILD_LINK_BASS)

################################################
# YBUILD_LINK_COMSUPPW
function(YBUILD_LINK_COMSUPPW target)
    target_link_libraries(${target} debug comsuppwd.lib)
    target_link_libraries(${target} optimized comsuppw.lib)
endfunction(YBUILD_LINK_COMSUPPW)

################################################
# YBUILD_LINK_MW10
function(YBUILD_LINK_MW10_DECODER target)
    set(MW10_SRC_DLL "${YBUILD_TPLIB_MW10DEC_PATH}/MW10Dec.dll")
    set(MW10_DST_DLL "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/MW10Dec.dll")
    
    get_property(MW10_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_MW10_COPY_ACTION_REGISTERED)
    if(NOT MW10_ALREADY_REGISTERED)
        add_custom_target(
            Mw10DecoderCopy
            DEPENDS "${MW10_DST_DLL}"
            )
        add_custom_command(
            OUTPUT "${MW10_DST_DLL}"
            COMMAND ${CMAKE_COMMAND} -E copy "${MW10_SRC_DLL}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
            MAIN_DEPENDENCY "${MW10_SRC_DLL}"
            VERBATIM
            )
        set_property(GLOBAL PROPERTY YBUILD_MW10_COPY_ACTION_REGISTERED ON)
    endif(NOT MW10_ALREADY_REGISTERED)
    add_dependencies(${target} Mw10DecoderCopy)
endfunction(YBUILD_LINK_MW10_DECODER)

function (YBUILD_ADD_INSTALLER_NSIS target name)
    if(NOT WIN32 OR NOT CMAKE_HOST_WIN32)
        message(FATAL_ERROR "The installer can be built only under the Win32 platform!")
    endif()

    set(SUBCOMMAND_ARGS "^(BOOTSTRAPPER_SCRIPT|NSIS_ARGS)$")

    foreach(arg ${ARGN})
        if("${arg}" MATCHES "${SUBCOMMAND_ARGS}")
            set(ARGMODE "${arg}")
        else()
            if("${ARGMODE}" STREQUAL "BOOTSTRAPPER_SCRIPT")
                file(GLOB BOOTSTRAPPER_NSI_SCRIPT "${arg}")
                set(ARGMODE)
            elseif("${ARGMODE}" STREQUAL "NSIS_ARGS")
                set(NSIS_ARGS "${NSIS_ARGS}" "${arg}")
            else()
                message(FATAL_ERROR "Unexpected argument \"${arg}\"")
            endif()
        endif()
    endforeach(arg)

    if(NOT DEFINED BOOTSTRAPPER_NSI_SCRIPT)
        set(BOOTSTRAPPER_NSI_SCRIPT "bootstrapper.nsi")
    endif()

    if("${YBUILD_LANGUAGE}" STREQUAL "ru_RU")
        set(LANGUAGE_NSIS Russian)
    elseif("${YBUILD_LANGUAGE}" STREQUAL "en_US")
        set(LANGUAGE_NSIS English)
    elseif("${YBUILD_LANGUAGE}" STREQUAL "en_GB")
        set(LANGUAGE_NSIS English)
    endif()

    set(NSIS_PROGRAM ${YBUILD_TPLIB_NSIS_PATH}/makensis.exe)

    file(TO_NATIVE_PATH "${CMAKE_BINARY_DIR}/_bin/${YBUILD_CFG_NAME}" FILE_PATH)
    set(BOOTSTRAPPER "${CMAKE_BINARY_DIR}/_install/${YBUILD_CFG_NAME}/${name}_${YBUILD_LANGUAGE}_${YBUILD_PRODUCT_VERSION}.exe")

    if("${CMAKE_MAKE_PROGRAM}" STREQUAL "nmake")
        file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/_install/${YBUILD_CFG_NAME}")
    endif()

    add_custom_target(
        ${target} ALL
        DEPENDS "${BOOTSTRAPPER}"
        SOURCES ${BOOTSTRAPPER_NSI_SCRIPT}
        )

    file(TO_NATIVE_PATH ${BOOTSTRAPPER} NSIS_Y_BOOTSTRAPPER)

    add_custom_command(
        OUTPUT "${BOOTSTRAPPER}"
        COMMAND ${NSIS_PROGRAM} 
            /DY_LANGUAGE=${YBUILD_LANGUAGE}
            /DY_LANGUAGE_NSIS=${LANGUAGE_NSIS}
            /DY_BOOTSTRAPPER=${NSIS_Y_BOOTSTRAPPER}
            /DY_PRODUCT=${name}
            /DY_FILE_PATH=${FILE_PATH}
            /DY_PRODUCT_VERSION=${YBUILD_PRODUCT_VERSION}
            /DY_BRAND_NAME=${CMAKE_BRAND_NAME}
            ${NSIS_ARGS}
            ${BOOTSTRAPPER_NSI_SCRIPT}
        VERBATIM
        )
endfunction(YBUILD_ADD_INSTALLER_NSIS)

################################################
# YBUILD_LINK_OPENCV
function(YBUILD_LINK_OPENCV target)
    set(OPENCV_DLLS "opencv.dll")
    
    target_link_libraries(${target} opencv)

    get_property(OPENCV_ALREADY_REGISTERED GLOBAL PROPERTY YBUILD_OPENCV_COPY_ACTION_REGISTERED)
    if(NOT OPENCV_ALREADY_REGISTERED)
        set(OPENCV_DST_DLLS)

        foreach(dll ${OPENCV_DLLS})
            set(OPENCV_DST_DLLS ${OPENCV_DST_DLLS} "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}")
        endforeach(dll)

        add_custom_target(
            opencvcopy
            DEPENDS ${OPENCV_DST_DLLS}
            )

        foreach(dll ${OPENCV_DLLS})
            add_custom_command(
                OUTPUT "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}/${dll}"
                COMMAND ${CMAKE_COMMAND} -E copy "${YBUILD_TPLIB_OPENCV_PATH}/bin/${dll}" "${YBUILD_FULL_RUNTIME_OUTPUT_DIRECTORY}"
                MAIN_DEPENDENCY "${YBUILD_TPLIB_OPENCV_PATH}/bin/${dll}"
                VERBATIM
                )
        endforeach(dll)
        set_property(GLOBAL PROPERTY YBUILD_OPENCV_COPY_ACTION_REGISTERED ON)
    endif(NOT OPENCV_ALREADY_REGISTERED)
    add_dependencies(${target} opencvcopy)
endfunction(YBUILD_LINK_OPENCV)

function(YBUILD_ADD_INSTALLER target name)
    if(NOT WIN32 OR NOT CMAKE_HOST_WIN32)
        message(FATAL_ERROR "The installer can be built only under the Win32 platform!")
    endif()
 
    set(SUBCOMMAND_ARGS "^(WXS_IN_FILES|WXS_FILES|BOOTSTRAPPER_SCRIPT|WIX_LANGUAGE_FILE|WIX_LANGUAGE_FILES|WIXLIBS|NSIS_ARGS|POSTFIX_VERSION)$")
    
    foreach(arg ${ARGN})
        if("${arg}" MATCHES "${SUBCOMMAND_ARGS}")
            set(ARGMODE "${arg}")
        else()
            if("${ARGMODE}" STREQUAL "WXS_IN_FILES")
                set(WXS_IN_FILES "${WXS_IN_FILES}" "${arg}")
            elseif("${ARGMODE}" STREQUAL "WXS_FILES")
                set(WXS_FILES "${WXS_FILES}" "${arg}")
            elseif("${ARGMODE}" STREQUAL "BOOTSTRAPPER_SCRIPT")
                file(GLOB BOOTSTRAPPER_NSI_SCRIPT "${arg}")
                set(ARGMODE)
            elseif("${ARGMODE}" STREQUAL "WIX_LANGUAGE_FILE")
                set(WIX_LANGUAGE_FILES "${arg}")
                set(ARGMODE)
            elseif("${ARGMODE}" STREQUAL "WIX_LANGUAGE_FILES")
                set(WIX_LANGUAGE_FILES "${WIX_LANGUAGE_FILES}" "${arg}")
            elseif("${ARGMODE}" STREQUAL "WIXLIBS")
                set(WIXLIBS "${WIXLIBS}" "${arg}")
            elseif("${ARGMODE}" STREQUAL "NSIS_ARGS")
                set(NSIS_ARGS "${NSIS_ARGS}" "${arg}")
            elseif("${ARGMODE}" STREQUAL "POSTFIX_VERSION")
                foreach(postfix "${arg}")
                    set(POSTFIX_VERSION "${postfix}")
                endforeach(arg)
            else()
                message(FATAL_ERROR "Unexpected argument \"${arg}\"")
            endif()
        endif()
    endforeach(arg)
    
    if(NOT DEFINED BOOTSTRAPPER_NSI_SCRIPT)
        set(BOOTSTRAPPER_NSI_SCRIPT "bootstrapper.nsi")
    endif()

    if("${YBUILD_LANGUAGE}" STREQUAL "ru_RU")
        set(LANGUAGE_NSIS Russian)
    elseif("${YBUILD_LANGUAGE}" STREQUAL "en_US")
        set(LANGUAGE_NSIS English)
    elseif("${YBUILD_LANGUAGE}" STREQUAL "en_GB")
        set(LANGUAGE_NSIS English)
    endif()

    set(CANDLE_PROGRAM ${YBUILD_TPLIB_WIX_PATH}/candle.exe)
    set(LIGHT_PROGRAM ${YBUILD_TPLIB_WIX_PATH}/light.exe)
    set(NSIS_PROGRAM ${YBUILD_TPLIB_NSIS_PATH}/makensis.exe)
    
    if(DEFINED WIX_LANGUAGE_FILES)
        file(GLOB LANG_STRINGS_FILES ${WIX_LANGUAGE_FILES})
    else()
        file(GLOB LANG_STRINGS_FILES "${YBUILD_LANGUAGE}.wxl")
    endif()
    
    foreach(lsf ${LANG_STRINGS_FILES})
        set(LANG_STRINGS "${LANG_STRINGS}" -loc "${lsf}")
    endforeach(lsf)

    set(INSTALLER_NAME "${name}_${YBUILD_LANGUAGE}.msi")
    set(INSTALLER "${CMAKE_BINARY_DIR}/_install/${YBUILD_CFG_NAME}/${INSTALLER_NAME}")
    set(BOOTSTRAPPER "${CMAKE_BINARY_DIR}/_install/${YBUILD_CFG_NAME}/${name}_${YBUILD_LANGUAGE}_${YBUILD_PRODUCT_VERSION}${POSTFIX_VERSION}.exe")
    
    add_custom_target(
        ${target} ALL
        DEPENDS "${BOOTSTRAPPER}"
        SOURCES ${WXS_IN_FILES} ${WXS_FILES} ${BOOTSTRAPPER_NSI_SCRIPT}
        )
    
    file(TO_NATIVE_PATH ${INSTALLER} NSIS_Y_INSTALLER)
    file(TO_NATIVE_PATH ${BOOTSTRAPPER} NSIS_Y_BOOTSTRAPPER)
    
    add_custom_command(
        OUTPUT "${BOOTSTRAPPER}"
        DEPENDS "${INSTALLER}"
        COMMAND ${NSIS_PROGRAM} 
            /DY_LANGUAGE=${YBUILD_LANGUAGE}
            /DY_LANGUAGE_NSIS=${LANGUAGE_NSIS}
            /DY_INSTALLER=${NSIS_Y_INSTALLER}
            /DY_INSTALLER_NAME=${INSTALLER_NAME}
            /DY_BOOTSTRAPPER=${NSIS_Y_BOOTSTRAPPER}
            /DY_PRODUCT=${name}
            ${NSIS_ARGS}
            ${BOOTSTRAPPER_NSI_SCRIPT}
        VERBATIM
        )
    
    set(FULL_VARSNAME "${CMAKE_CURRENT_BINARY_DIR}/${name}_cmake_vars.cmake")
    set(YBUILD_ROOT "${CMAKE_SOURCE_DIR}")
    set(YBUILD_3RDPARTY_FILES ${CMAKE_SOURCE_DIR}/3rdparty)

    if(MSVC)
        if(MSVC_VERSION EQUAL 1400)
            set(YBUILD_VC_CRT_MERGE_MODULE Microsoft_VC80_CRT_x86.msm)
            set(YBUILD_VC_ATL_MERGE_MODULE Microsoft_VC80_ATL_x86.msm)
            set(YBUILD_VC_MFC_MERGE_MODULE Microsoft_VC80_MFC_x86.msm)
        endif(MSVC_VERSION EQUAL 1400)

        if(MSVC_VERSION EQUAL 1500)
            set(YBUILD_VC_CRT_MERGE_MODULE Microsoft_VC90_CRT_x86.msm)
            set(YBUILD_VC_ATL_MERGE_MODULE Microsoft_VC90_ATL_x86.msm)
            set(YBUILD_VC_MFC_MERGE_MODULE Microsoft_VC90_MFC_x86.msm)
        endif(MSVC_VERSION EQUAL 1500)

        if(MSVC_VERSION EQUAL 1600)
            set(YBUILD_VC_CRT_MERGE_MODULE Microsoft_VC100_CRT_x86.msm)
            set(YBUILD_VC_ATL_MERGE_MODULE Microsoft_VC100_ATL_x86.msm)
            set(YBUILD_VC_MFC_MERGE_MODULE Microsoft_VC100_MFC_x86.msm)
        endif(MSVC_VERSION EQUAL 1600)
    endif(MSVC)
    
    get_cmake_property(VARLIST VARIABLES)
    file(WRITE "${FULL_VARSNAME}" "\# Generated by YBuild.cmake
    ")
    foreach(myvar ${VARLIST})
        YBUILD_ESCAPE(ESCAPED_VAR "${${myvar}}")
        string(REPLACE \\ \\\\ MYVAR_ESCAPED_NAME ${myvar})
        file(APPEND "${FULL_VARSNAME}" "SET(${MYVAR_ESCAPED_NAME} \"${ESCAPED_VAR}\")
        ")
    endforeach(myvar)
    
    set(FULL_CMAKE_SCRIPT_NAME "${CMAKE_CURRENT_BINARY_DIR}/${name}_installer_configure.cmake")
    file(WRITE "${FULL_CMAKE_SCRIPT_NAME}" "\# Generated by YBuild.cmake
    ")
    file(APPEND "${FULL_CMAKE_SCRIPT_NAME}" "include(\"${FULL_VARSNAME}\")
    ")
    file(APPEND "${FULL_CMAKE_SCRIPT_NAME}" "set(YBUILD_INSTALL_FILES \"${YBUILD_BASE_RUNTIME_OUTPUT_DIRECTORY}/\${YBUILD_IN_CFG}\")
    ")
    file(APPEND "${FULL_CMAKE_SCRIPT_NAME}" "configure_file(\"\${YBUILD_IN_FILE}\" \"\${YBUILD_OUT_FILE}\")
    ")
    
    foreach(wxsin ${WXS_IN_FILES})
        file(GLOB FULL_WXSINNAME "${wxsin}")
        get_filename_component(WXSINNAME "${FULL_WXSINNAME}" NAME)
        string(REPLACE ".in" "${NULL_ARGUMENT}" WXSNAME "${WXSINNAME}")
        string(REPLACE ".wxs" ".wixobj" WIXOBJNAME "${WXSNAME}")
        
        set(FULL_WXSNAME "${CMAKE_CURRENT_BINARY_DIR}/${YBUILD_CFG_NAME}/${WXSNAME}")
        set(FULL_WIXOBJNAME "${CMAKE_CURRENT_BINARY_DIR}/${YBUILD_CFG_NAME}/${WIXOBJNAME}")
        set(WIXOBJ_FILES "${WIXOBJ_FILES}" "${FULL_WIXOBJNAME}")
        
        set(YBUILD_IN_FILE_ARG "-DYBUILD_IN_FILE=${FULL_WXSINNAME}")
        set(YBUILD_OUT_FILE_ARG "-DYBUILD_OUT_FILE=${FULL_WXSNAME}")

        add_custom_command(
            OUTPUT "${FULL_WXSNAME}"
            DEPENDS "${FULL_WXSINNAME}" "${FULL_VARSNAME}" "${FULL_CMAKE_SCRIPT_NAME}"
            COMMAND "${CMAKE_COMMAND}" "${YBUILD_IN_FILE_ARG}" "${YBUILD_OUT_FILE_ARG}" -DYBUILD_IN_CFG=${YBUILD_CFG_NAME} -P "${FULL_CMAKE_SCRIPT_NAME}"
            VERBATIM
            )

        add_custom_command(
            OUTPUT "${FULL_WIXOBJNAME}"
            DEPENDS "${FULL_WXSNAME}"
            COMMAND ${CANDLE_PROGRAM} -out "${FULL_WIXOBJNAME}" "${FULL_WXSNAME}"
            VERBATIM
            )
    endforeach(wxsin)
    
    foreach(wxs ${WXS_FILES})
        set(FULL_WXSNAME "${wxs}")
        get_filename_component(WXSNAME "${FULL_WXSNAME}" NAME)
        string(REPLACE ".wxs" ".wixobj" WIXOBJNAME "${WXSNAME}")

        set(FULL_WIXOBJNAME "${CMAKE_CURRENT_BINARY_DIR}/${YBUILD_CFG_NAME}/${WIXOBJNAME}")
        set(WIXOBJ_FILES "${WIXOBJ_FILES}" "${FULL_WIXOBJNAME}")

        add_custom_command(
            OUTPUT "${FULL_WIXOBJNAME}"
            DEPENDS "${FULL_WXSNAME}"
            COMMAND ${CANDLE_PROGRAM} -out "${FULL_WIXOBJNAME}" "${FULL_WXSNAME}"
            VERBATIM
            )
    endforeach(wxs)
        
    add_custom_command(
        OUTPUT "${INSTALLER}"
        DEPENDS ${WIXOBJ_FILES}
        COMMAND ${LIGHT_PROGRAM}
            ${LANG_STRINGS}
            -out "${INSTALLER}"
            ${WIXOBJ_FILES}
            ${WIXLIBS}
        VERBATIM
        )
endfunction(YBUILD_ADD_INSTALLER)

macro(YBUILD_DEFINE_GUID result guid)
	string(REGEX REPLACE \(........\).\(....\).\(....\).\(..\)\(..\).\(............\) "0x\\1,0x\\2,0x\\3,0x\\4,0x\\5" ${result} "${guid}")
	string(REGEX REPLACE \(..\)\(..\)\(..\)\(..\)\(..\)\(..\) "${${result}},0x\\1,0x\\2,0x\\3,0x\\4,0x\\5,0x\\6" ${result} "${CMAKE_MATCH_6}")
endmacro(YBUILD_DEFINE_GUID)

# Определим глобальные свойства
define_property(GLOBAL PROPERTY YBUILD_INCLUDED BRIEF_DOCS "YBuild inclusion marker" FULL_DOCS "YBuild inclusion marker")
set_property(GLOBAL PROPERTY YBUILD_INCLUDED ON)

define_property(GLOBAL PROPERTY YBUILD_REGISTERED_LIBRARY_NAMES BRIEF_DOCS "YBuild registered library names" FULL_DOCS "YBuild registered library names")
define_property(GLOBAL PROPERTY YBUILD_REGISTERED_LIBRARY_ACTIONS BRIEF_DOCS "YBuild registered library link actions" FULL_DOCS "YBuild registered library link actions")

define_property(GLOBAL PROPERTY YBUILD_ADV601_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild AW_ADV601 copy action was registered" FULL_DOCS "YBuild AW_ADV601 copy action was registered")
define_property(GLOBAL PROPERTY YBUILD_W95SCM_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild w95scm copy action was registered" FULL_DOCS "YBuild w95scm copy action was registered")
define_property(GLOBAL PROPERTY YBUILD_BASS_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild bass copy action was registered" FULL_DOCS "YBuild bass copy action was registered")
define_property(GLOBAL PROPERTY YBUILD_MW10_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild MW10Dec copy action was registered" FULL_DOCS "YBuild bass copy action was registered")
define_property(GLOBAL PROPERTY YBUILD_FFMPEG_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild ffmpeg copy action was registered" FULL_DOCS "YBuild ffmpeg copy action was registered")
define_property(GLOBAL PROPERTY YBUILD_IPP_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild ipp copy action was registered" FULL_DOCS "YBuild ipp copy action was registered")
define_property(GLOBAL PROPERTY YBUILD_AMPFFT_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild ampfft copy action was registered" FULL_DOCS "YBuild ampfft copy action was registered")
define_property(GLOBAL PROPERTY YBUILD_HW_CODECS_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild hardware codecs copy action was registered" FULL_DOCS "YBuild hardware codecs copy action was registered")
define_property(GLOBAL PROPERTY YBUILD_FTD2XX_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild ftd2xx copy action was registered" FULL_DOCS "YBuild ftd2xx copy action was registered")
define_property(GLOBAL PROPERTY YBUILD_OPENCV_COPY_ACTION_REGISTERED BRIEF_DOCS "YBuild opencv copy action was registered" FULL_DOCS "YBuild opencv copy action was registered")


define_property(GLOBAL PROPERTY YBUILD_INVOCATION_COUNTER BRIEF_DOCS "YBuild invocation counter" FULL_DOCS "YBuild invocation counter")

set_property(GLOBAL PROPERTY YBUILD_ADV601_COPY_ACTION_REGISTERED OFF)
set_property(GLOBAL PROPERTY YBUILD_W95SCM_COPY_ACTION_REGISTERED OFF)
set_property(GLOBAL PROPERTY YBUILD_BASS_COPY_ACTION_REGISTERED OFF)
set_property(GLOBAL PROPERTY YBUILD_MW10_COPY_ACTION_REGISTERED OFF)
set_property(GLOBAL PROPERTY YBUILD_FFMPEG_COPY_ACTION_REGISTERED OFF)
set_property(GLOBAL PROPERTY YBUILD_IPP_COPY_ACTION_REGISTERED OFF)
set_property(GLOBAL PROPERTY YBUILD_AMPFFT_COPY_ACTION_REGISTERED OFF)
set_property(GLOBAL PROPERTY YBUILD_HW_CODECS_COPY_ACTION_REGISTERED OFF)
set_property(GLOBAL PROPERTY YBUILD_FTD2XX_COPY_ACTION_REGISTERED OFF)
set_property(GLOBAL PROPERTY YBUILD_OPENCV_COPY_ACTION_REGISTERED OFF)


set_property(GLOBAL PROPERTY YBUILD_INVOCATION_COUNTER 0)

###################################
# Определим общие настройки сборки

# Уберем лишние конфигурации.
set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE INTERNAL "" FORCE)

if(NOT MSVC_IDE AND NOT DEFINED CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Konfiguraciya" FORCE)
endif(NOT MSVC_IDE AND NOT DEFINED CMAKE_BUILD_TYPE)
