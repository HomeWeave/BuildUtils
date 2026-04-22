include(FetchContent)
include(CMakeParseArguments)
include(UseJava)

string(CONCAT EMBED_PY_CODE
"import os\n"
"import re\n"
"import sys\n"
"import textwrap\n"
"\n"
"def to_c_var(inp):\n"
"  return re.sub('[^a-zA-Z0-9]', '_', inp)\n"
"\n"
"def write_cc_data(inp_path, out, var_name, rel_path):\n"
"  with open(inp_path, 'rb') as inp:\n"
"    data = inp.read()\n"
"  out.write(f'const unsigned char {var_name}_data[] = {{' + '\\n')\n"
"  out.write(''.join(hex(x) + ', ' for x in data) + '0x00')\n"
"  out.write('};\\n')\n"
"\n"
"  out.write(f'const unsigned {var_name}_size = ' + str(len(data)) + ';\\n')\n"
"\n"
"  out.write(f'const char* {var_name}_path = \"{rel_path}\";' + '\\n\\n')\n"
"\n"
"\n"
"def write_h_data(out, var_name):\n"
"  out.write(f'extern const unsigned char {var_name}_data[];' + '\\n')\n"
"  out.write(f'extern const unsigned {var_name}_size;' + '\\n')\n"
"  out.write(f'extern const char* {var_name}_path;' + '\\n\\n')\n"
"\n"
"\n"
"target = sys.argv[1]\n"
"out_dir = sys.argv[2]\n"
"base_dir = os.path.abspath(sys.argv[3])\n"
"files = [os.path.abspath(x) for x in sys.argv[4:]]\n"
"if not files:\n"
"  files = [os.path.join(d, f) for d, _, fs in os.walk(base_dir) for f in fs]\n"
"\n"
"target_c_var = target\n"
"\n"
"file_count = len(files)\n"
"if not file_count:\n"
"  raise ValueError('No files to process.')\n"
"\n"
"h_out = os.path.join(out_dir, target + '.h')\n"
"cc_out = os.path.join(out_dir, target + '.cc')\n"
"\n"
"h_content = textwrap.dedent(f'''\n"
"struct {target_c_var}FilesStruct {{\n"
"  const unsigned char* data;\n"
"  unsigned length;\n"
"  const char* path;\n"
"}};\n"
"\n"
"extern {target_c_var}FilesStruct all_{target_c_var}_data[];\n"
"const int all_{target_c_var}_size = {file_count};\n"
"\n"
"''')\n"
"cc_content = textwrap.dedent(f'''\n"
"#include <{h_out}>\n"
"\n"
"''')\n"
"with open(h_out, 'w') as h, open(cc_out, 'w') as cc:\n"
"  h.write(h_content)\n"
"  cc.write(cc_content)\n"
"\n"
"  all_data = []\n"
"  for input_file in files:\n"
"    rel_path = os.path.relpath(input_file, start=base_dir)\n"
"    var = to_c_var(rel_path)\n"
"    write_cc_data(input_file, cc, var, rel_path)\n"
"    write_h_data(h, var)\n"
"\n"
"    all_data.append(f'{{{var}_data, {var}_size, {var}_path}}')\n"
"\n"
"  cc.write(f'{target_c_var}FilesStruct all_{target_c_var}_data[]')\n"
"  cc.write(' = {\\n')\n"
"  cc.write(',\\n'.join(all_data))\n"
"  cc.write('\\n};\\n')\n")


function(conditional_file_update)
    CMakeParseArguments(
        PARSED_ARGS
        ""
        "DEST;CONTENT"
        ""
        ${ARGN}
    )
    if (NOT PARSED_ARGS_DEST)
        message(FATAL_ERROR "No DEST provided.")
    endif()
    if (NOT PARSED_ARGS_CONTENT)
        message(FATAL_ERROR "No CONTENT provided.")
    endif()

    set(TEMP_FILE_PATH ${CMAKE_BINARY_DIR}/conditional_write)
    file(WRITE ${TEMP_FILE_PATH} "${PARSED_ARGS_CONTENT}")
    file(SHA256 NEW_HASH "${TEMP_FILE_PATH}")

    file(SHA256 OLD_HASH "${PARSED_ARGS_DEST}")

    if (NOT "${OLD_HASH}" STREQUAL "${NEW_HASH}")
        file(WRITE ${PARSED_ARGS_DEST} "${PARSED_ARGS_CONTENT}")
    endif()
endfunction()

function(git_fetch_content name git_repo git_tag)
    set(FETCHCONTENT_QUIET OFF)
    FetchContent_Declare(${name} GIT_REPOSITORY "${git_repo}"
                         GIT_TAG "${git_tag}")
    FetchContent_GetProperties(${name})
    if(NOT ${name}_POPULATED)
        FetchContent_Populate(${name})
        if (EXISTS "${${name}_SOURCE_DIR}/CMakeLists.txt")
            add_subdirectory(${${name}_SOURCE_DIR} ${${name}_BINARY_DIR})
        endif()
    endif()
    set(${name}_SOURCE_DIR ${${name}_SOURCE_DIR} PARENT_SCOPE)
endfunction()

function(git_fetch_content_v2)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "NAME;URL;VERSION;CMAKE_DIR;PATCH"
        ""
        ${ARGN}
    )
    if(NOT PARSED_ARGS_NAME)
        message(FATAL_ERROR "You must provide a NAME arg.")
    endif()
    if (NOT PARSED_ARGS_URL)
        message(FATAL_ERROR "You must provide a URL argumrnt.")
    endif()
    if (NOT PARSED_ARGS_VERSION)
        message(FATAL_ERROR "You must provide a VERSION argumrnt.")
    endif()
    if (NOT PARSED_ARGS_CMAKE_DIR)
        set(PARSED_ARGS_CMAKE_DIR ".")
    endif()

    set(FETCHCONTENT_QUIET OFF)
    FetchContent_Declare(${PARSED_ARGS_NAME} GIT_REPOSITORY "${PARSED_ARGS_URL}"
                         GIT_TAG "${PARSED_ARGS_VERSION}")

    FetchContent_GetProperties(${PARSED_ARGS_NAME})
    if(NOT ${PARSED_ARGS_NAME}_POPULATED)
        FetchContent_Populate(${PARSED_ARGS_NAME})

        if (PARSED_ARGS_PATCH)
            execute_process(
                COMMAND ${GIT_EXECUTABLE} apply ${PARSED_ARGS_PATCH}
                WORKING_DIRECTORY ${${PARSED_ARGS_NAME}_SOURCE_DIR})
        endif()

        if (EXISTS "${${PARSED_ARGS_NAME}_SOURCE_DIR}/${PARSED_ARGS_CMAKE_DIR}/CMakeLists.txt")
            add_subdirectory(
                ${${PARSED_ARGS_NAME}_SOURCE_DIR}/${PARSED_ARGS_CMAKE_DIR}
                ${${PARSED_ARGS_NAME}_BINARY_DIR})
        endif()
    endif()
    set(${PARSED_ARGS_NAME}_SOURCE_DIR ${${PARSED_ARGS_NAME}_SOURCE_DIR}
        PARENT_SCOPE)

    # Custom exports.
    if(DEFINED ANTON_SUBPROJECT_VAR_EXPORTS)
        foreach(var IN ITEMS ${ANTON_SUBPROJECT_VAR_EXPORTS})
            set(${var} "${${var}}" PARENT_SCOPE)
        endforeach()
    endif()
endfunction()


function(ensure_out_of_source_builds)
    if ( ${CMAKE_SOURCE_DIR} STREQUAL ${CMAKE_BINARY_DIR} )
        message(FATAL_ERROR "In-source builds not allowed.")
    endif()
endfunction()

function(internal_proto_path_to_target)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "PATH;OUT_TARGET"
        ""
        ${ARGN}
    )
    if (NOT PARSED_ARGS_PATH)
        message(FATAL_ERROR "PATH arg missing.")
    endif()
    if (NOT PARSED_ARGS_OUT_TARGET)
        message(FATAL_ERROR "OUT_TARGET arg missing.")
    endif()

    string(REGEX REPLACE "[^a-zA-Z0-9]" "_" TARGET ${PARSED_ARGS_PATH})
    set(${PARSED_ARGS_OUT_TARGET} "${TARGET}" PARENT_SCOPE)
endfunction()

function(build_cc_proto_library)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "TARGET;INCLUDE_DIR"
        "SOURCES;DEPENDENCIES;LINK_LIBRARIES"
        ${ARGN}
    )
    if(NOT PARSED_ARGS_TARGET)
        message(FATAL_ERROR "You must provide a TARGET arg.")
    endif()

    add_library(${PARSED_ARGS_TARGET} STATIC EXCLUDE_FROM_ALL ${PARSED_ARGS_SOURCES})
    target_include_directories(${PARSED_ARGS_TARGET} PUBLIC ${PARSED_ARGS_INCLUDE_DIR})

    if (PARSED_ARGS_LINK_LIBRARIES)
        target_link_libraries(${PARSED_ARGS_TARGET} ${PARSED_ARGS_LINK_LIBRARIES})
    endif()

    if (PARSED_ARGS_DEPENDENCIES)
        add_dependencies(${PARSED_ARGS_TARGET} ${PARSED_ARGS_DEPENDENCIES})
    endif()

    set(${PARSED_ARGS_TARGET} ${PARSED_ARGS_TARGET} PARENT_SCOPE)
endfunction()

function(internal_process_cc_proto)
    cmake_parse_arguments(
        PARSED_ARGS
        "PROTO_GENERATE;PROTO_BUILD"
        "SRC_BASE_PATH;SRC_REL_PATH;SRC_CORE_NAME;OUTPUT_BASE;PROTO_COPY_TARGET;HAS_SERVICES;PROTO_GEN_DIR"
        "PROTO_DEPS"
        ${ARGN}
    )
    if(NOT PARSED_ARGS_OUTPUT_BASE)
        message(FATAL_ERROR "You must provide a OUTPUT_BASE arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_REL_PATH)
        message(FATAL_ERROR "You must provide a SRC_REL_PATH arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_CORE_NAME)
        message(FATAL_ERROR "You must provide a SRC_CORE_NAME arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_BASE_PATH)
        message(FATAL_ERROR "You must provide a SRC_BASE_PATH arg.")
    endif()
    if(NOT PARSED_ARGS_PROTO_COPY_TARGET)
        message(FATAL_ERROR "You must provide a PROTO_COPY_TARGET arg.")
    endif()

    set(PROTO_ROOT_DIR "${PARSED_ARGS_SRC_BASE_PATH}")
    set(PROTO_REL_PATH "${PARSED_ARGS_SRC_REL_PATH}")
    string(CONCAT INPUT_PROTO_FILE
           "${PARSED_ARGS_SRC_BASE_PATH}/"
           "${PARSED_ARGS_SRC_REL_PATH}/"
           "${PARSED_ARGS_SRC_CORE_NAME}.proto")
    set(PROTO_CORE_NAME "${PARSED_ARGS_SRC_CORE_NAME}")
    set(PROTO_SERVICES "${PARSED_ARGS_HAS_SERVICES}")
    set(COPY_PROTO_TARGET "${PARSED_ARGS_PROTO_COPY_TARGET}")

    if (PARSED_ARGS_PROTO_GEN_DIR)
        set(CC_GEN_ROOT_DIR "${PARSED_ARGS_PROTO_GEN_DIR}/gen-cc-proto")
    else()
        set(CC_GEN_ROOT_DIR "${PARSED_ARGS_OUTPUT_BASE}")
    endif()

    internal_proto_path_to_target(
        PATH "${PROTO_REL_PATH}/${PROTO_CORE_NAME}.proto"
        OUT_TARGET CC_LIB_TARGET)

    file(MAKE_DIRECTORY ${CC_GEN_ROOT_DIR})

    list(APPEND output_files
        "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.pb.cc"
        "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.pb.h")
    list(APPEND proto_srcs
        "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.pb.cc")

    set(GRPC_PARAM "")
    if(PROTO_SERVICES)
        list(APPEND output_files
             "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.cc"
             "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.h")
        list(APPEND proto_srcs
             "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.cc")

        if (TARGET grpc_cpp_plugin)
            set(GRPC_PARAM --plugin=protoc-gen-grpc=$<TARGET_FILE:grpc_cpp_plugin>)
            set(GRPC_PARAM ${GRPC_PARAM} --grpc_out ${CC_GEN_ROOT_DIR})
        endif()
    endif()

    if (PARSED_ARGS_PROTO_GENERATE)
        FetchContent_GetProperties(protobuf)  # Assume it's called protobuf.
        if(NOT protobuf_POPULATED)
          message(FATAL "Unable to locate protobuf dependency.")
        endif()
        set(PB_SRC ${protobuf_SOURCE_DIR})

        message(STATUS "  - Will generate: ${output_files}")

        add_custom_command(
          OUTPUT ${output_files}
          COMMAND $<TARGET_FILE:protoc>
               --cpp_out "${CC_GEN_ROOT_DIR}"
               -I "${PROTO_ROOT_DIR}"
               -I "${PB_SRC}/src"
               ${GRPC_PARAM}
               "${INPUT_PROTO_FILE}"
          WORKING_DIRECTORY "${PROTO_ROOT_DIR}"
          DEPENDS "${INPUT_PROTO_FILE}"
        )
        add_custom_target(
            ${CC_LIB_TARGET}_cc_genfiles_target
            DEPENDS ${output_files})
        add_dependencies(
            ${CC_LIB_TARGET}_cc_genfiles_target
            ${COPY_PROTO_TARGET})
        if (TARGET protoc)
            add_dependencies(${CC_LIB_TARGET}_cc_genfiles_target protoc)
        endif()
    endif()

    if (PARSED_ARGS_PROTO_BUILD)
        set(CC_LINK_LIBS libprotobuf)
        set(CC_DEPS libprotobuf)

        if(PROTO_SERVICES AND TARGET grpc_cpp_plugin)
            list(APPEND CC_LINK_LIBS grpc++_unsecure)
            list(APPEND CC_DEPS grpc_cpp_plugin)
        endif()

        if (PARSED_ARGS_PROTO_GENERATE)
            list(APPEND CC_DEPS ${CC_LIB_TARGET}_cc_genfiles_target)
        endif()

        foreach(proto_deps IN ITEMS ${PARSED_ARGS_PROTO_DEPS})
            internal_proto_path_to_target(
                PATH ${proto_deps}
                OUT_TARGET PROTO_TARGET)
            list(APPEND CC_LINK_LIBS ${PROTO_TARGET})
        endforeach()

        build_cc_proto_library(
            TARGET ${CC_LIB_TARGET}
            INCLUDE_DIR ${CC_GEN_ROOT_DIR}
            SOURCES ${output_files}
            LINK_LIBRARIES ${CC_LINK_LIBS}
            DEPENDENCIES ${CC_DEPS}
        )
        set(CC_LIB_TARGET ${CC_LIB_TARGET} PARENT_SCOPE)
    else()
        set(CC_LIB_TARGET ${CC_LIB_TARGET}_cc_genfiles_target PARENT_SCOPE)
    endif()
endfunction()

function(internal_process_py_proto)
    cmake_parse_arguments(
        PARSED_ARGS
        "PROTO_GENERATE;PROTO_BUILD"
        "SRC_BASE_PATH;SRC_REL_PATH;SRC_CORE_NAME;OUTPUT_BASE;PROTO_COPY_TARGET;PROTO_GEN_DIR"
        "PROTO_DEPS"
        ${ARGN}
    )
    if(NOT PARSED_ARGS_OUTPUT_BASE)
        message(FATAL_ERROR "You must provide a OUTPUT_BASE arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_REL_PATH)
        message(FATAL_ERROR "You must provide a SRC_REL_PATH arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_CORE_NAME)
        message(FATAL_ERROR "You must provide a SRC_CORE_NAME arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_BASE_PATH)
        message(FATAL_ERROR "You must provide a SRC_BASE_PATH arg.")
    endif()
    if(NOT PARSED_ARGS_PROTO_COPY_TARGET)
        message(FATAL_ERROR "You must provide a PROTO_COPY_TARGET arg.")
    endif()

    set(PROTO_ROOT_DIR "${PARSED_ARGS_SRC_BASE_PATH}")
    set(PROTO_REL_PATH "${PARSED_ARGS_SRC_REL_PATH}")
    string(CONCAT INPUT_PROTO_FILE
           "${PARSED_ARGS_SRC_BASE_PATH}/"
           "${PARSED_ARGS_SRC_REL_PATH}/"
           "${PARSED_ARGS_SRC_CORE_NAME}.proto")
    set(PROTO_CORE_NAME "${PARSED_ARGS_SRC_CORE_NAME}")
    set(COPY_PROTO_TARGET "${PARSED_ARGS_PROTO_COPY_TARGET}")

    if (PARSED_ARGS_PROTO_GEN_DIR)
        set(PY_GEN_ROOT_DIR "${PARSED_ARGS_PROTO_GEN_DIR}/gen-py-proto")
    else()
        set(PY_GEN_ROOT_DIR "${PARSED_ARGS_OUTPUT_BASE}")
    endif()

    set(OUTPUT_FILE
        "${PY_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}_pb2.py")

    internal_proto_path_to_target(
        PATH "${PROTO_REL_PATH}/${PROTO_CORE_NAME}.proto"
        OUT_TARGET PY_TARGET)

    file(MAKE_DIRECTORY ${PY_GEN_ROOT_DIR})

    if (PARSED_ARGS_PROTO_GENERATE)
        FetchContent_GetProperties(protobuf)  # Assume it's called protobuf.
        if(NOT protobuf_POPULATED)
          message(FATAL "Unable to locate protobuf dependency.")
        endif()
        set(PB_SRC ${protobuf_SOURCE_DIR})

        message(STATUS "  - Will generate: ${OUTPUT_FILE}")

        add_custom_command(
          OUTPUT ${OUTPUT_FILE}
          COMMAND $<TARGET_FILE:protoc>
               --python_out "${PY_GEN_ROOT_DIR}"
               -I "${PROTO_ROOT_DIR}"
               -I "${PB_SRC}/src"
               "${INPUT_PROTO_FILE}"
          WORKING_DIRECTORY "${PROTO_ROOT_DIR}"
          DEPENDS "${INPUT_PROTO_FILE}"
        )
        add_custom_target(${PY_TARGET}_py_genfiles_target
                          DEPENDS ${OUTPUT_FILE})
        if (TARGET protoc)
            add_dependencies(${PY_TARGET}_py_genfiles_target protoc)
        endif()
        add_dependencies(${PY_TARGET}_py_genfiles_target ${COPY_PROTO_TARGET})
    endif()

    if (PARSED_ARGS_PROTO_BUILD)
        set(GENFILES_TARGET "${PY_TARGET}_py_genfiles_target" PARENT_SCOPE)
        set(PY_PROTO_ROOT_DIR "${PY_GEN_ROOT_DIR}" PARENT_SCOPE)
        set(OUTPUT_FILE "${OUTPUT_FILE}" PARENT_SCOPE)
    endif()
endfunction()

function(internal_process_java_proto)
    cmake_parse_arguments(
        PARSED_ARGS
        "PROTO_GENERATE;PROTO_BUILD"
        "SRC_BASE_PATH;SRC_REL_PATH;SRC_CORE_NAME;PKG;OUTPUT_BASE;PROTO_COPY_TARGET;PROTO_GEN_DIR"
        "PROTO_DEPS"
        ${ARGN}
    )
    if(NOT PARSED_ARGS_OUTPUT_BASE)
        message(FATAL_ERROR "You must provide a OUTPUT_BASE arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_REL_PATH)
        message(FATAL_ERROR "You must provide a SRC_REL_PATH arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_CORE_NAME)
        message(FATAL_ERROR "You must provide a SRC_CORE_NAME arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_BASE_PATH)
        message(FATAL_ERROR "You must provide a SRC_BASE_PATH arg.")
    endif()
    if(NOT PARSED_ARGS_PROTO_COPY_TARGET)
        message(FATAL_ERROR "You must provide a PROTO_COPY_TARGET arg.")
    endif()
    if(NOT PARSED_ARGS_PKG)
        message(FATAL_ERROR "You must provide a PKG arg.")
    endif()

    set(PROTO_ROOT_DIR "${PARSED_ARGS_SRC_BASE_PATH}")
    set(PROTO_REL_PATH "${PARSED_ARGS_SRC_REL_PATH}")
    string(REPLACE "." "/" PACKAGE_PATH "${PARSED_ARGS_PKG}")
    string(CONCAT INPUT_PROTO_FILE
           "${PARSED_ARGS_SRC_BASE_PATH}/"
           "${PARSED_ARGS_SRC_REL_PATH}/"
           "${PARSED_ARGS_SRC_CORE_NAME}.proto")
    set(PROTO_CORE_NAME "${PARSED_ARGS_SRC_CORE_NAME}")
    set(COPY_PROTO_TARGET "${PARSED_ARGS_PROTO_COPY_TARGET}")

    if (PARSED_ARGS_PROTO_GEN_DIR)
        set(JAVA_GEN_ROOT_DIR "${PARSED_ARGS_PROTO_GEN_DIR}/gen-java-proto")
    else()
        set(JAVA_GEN_ROOT_DIR "${PARSED_ARGS_OUTPUT_BASE}")
    endif()

    set(OUTPUT_FILE
        "${JAVA_GEN_ROOT_DIR}/${PACKAGE_PATH}/${PROTO_CORE_NAME}.java")

    internal_proto_path_to_target(
        PATH "${PROTO_REL_PATH}/${PROTO_CORE_NAME}.proto"
        OUT_TARGET JAVA_TARGET)

    file(MAKE_DIRECTORY ${JAVA_GEN_ROOT_DIR})

    if (PARSED_ARGS_PROTO_GENERATE)
        FetchContent_GetProperties(protobuf)  # Assume it's called protobuf.
        if(NOT protobuf_POPULATED)
          message(FATAL "Unable to locate protobuf dependency.")
        endif()
        set(PB_SRC ${protobuf_SOURCE_DIR})

        message(STATUS "  - Will generate: ${OUTPUT_FILE}")

        add_custom_command(
          OUTPUT ${OUTPUT_FILE}
          COMMAND $<TARGET_FILE:protoc>
               --java_out "${JAVA_GEN_ROOT_DIR}"
               -I "${PROTO_ROOT_DIR}"
               -I "${PB_SRC}/src"
               "${INPUT_PROTO_FILE}"
          WORKING_DIRECTORY "${PROTO_ROOT_DIR}"
          DEPENDS "${INPUT_PROTO_FILE}"
        )

        add_custom_target(${JAVA_TARGET}_java_genfiles_target
                          DEPENDS ${OUTPUT_FILE})
        if (TARGET protoc)
            add_dependencies(${JAVA_TARGET}_java_genfiles_target protoc)
        endif()
        add_dependencies(${JAVA_TARGET}_java_genfiles_target ${COPY_PROTO_TARGET})
    endif()

    if (PARSED_ARGS_PROTO_BUILD)
        set(GENFILES_TARGET "${JAVA_TARGET}_java_genfiles_target" PARENT_SCOPE)
        set(JAVA_PROTO_ROOT_DIR "${JAVA_GEN_ROOT_DIR}" PARENT_SCOPE)
        set(OUTPUT_FILE "${OUTPUT_FILE}" PARENT_SCOPE)
    endif()
endfunction()

function(internal_process_ts_proto)
    cmake_parse_arguments(
        PARSED_ARGS
        "PROTO_GENERATE;PROTO_BUILD"
        "SRC_BASE_PATH;SRC_REL_PATH;SRC_CORE_NAME;OUTPUT_BASE;PROTO_COPY_TARGET;TS_PLUGIN;PROTO_GEN_DIR"
        "PROTO_DEPS"
        ${ARGN}
    )
    if(NOT PARSED_ARGS_OUTPUT_BASE)
        message(FATAL_ERROR "You must provide a OUTPUT_BASE arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_REL_PATH)
        message(FATAL_ERROR "You must provide a SRC_REL_PATH arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_CORE_NAME)
        message(FATAL_ERROR "You must provide a SRC_CORE_NAME arg.")
    endif()
    if(NOT PARSED_ARGS_SRC_BASE_PATH)
        message(FATAL_ERROR "You must provide a SRC_BASE_PATH arg.")
    endif()
    if(NOT PARSED_ARGS_PROTO_COPY_TARGET)
        message(FATAL_ERROR "You must provide a PROTO_COPY_TARGET arg.")
    endif()
    if(NOT PARSED_ARGS_TS_PLUGIN)
        message(FATAL_ERROR "You must provide a TS_PLUGIN arg.")
    endif()

    set(PROTO_ROOT_DIR "${PARSED_ARGS_SRC_BASE_PATH}")
    set(PROTO_REL_PATH "${PARSED_ARGS_SRC_REL_PATH}")
    string(CONCAT INPUT_PROTO_FILE
           "${PARSED_ARGS_SRC_BASE_PATH}/"
           "${PARSED_ARGS_SRC_REL_PATH}/"
           "${PARSED_ARGS_SRC_CORE_NAME}.proto")
    set(PROTO_CORE_NAME "${PARSED_ARGS_SRC_CORE_NAME}")
    set(COPY_PROTO_TARGET "${PARSED_ARGS_PROTO_COPY_TARGET}")

    if (PARSED_ARGS_PROTO_GEN_DIR)
        set(TS_GEN_ROOT_DIR "${PARSED_ARGS_PROTO_GEN_DIR}/gen-ts-proto")
    else()
        set(TS_GEN_ROOT_DIR "${PARSED_ARGS_OUTPUT_BASE}")
    endif()

    set(OUTPUT_FILE
        "${TS_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.ts")

    internal_proto_path_to_target(
        PATH "${PROTO_REL_PATH}/${PROTO_CORE_NAME}.proto"
        OUT_TARGET TS_TARGET)

    file(MAKE_DIRECTORY ${TS_GEN_ROOT_DIR})

    if (PARSED_ARGS_PROTO_GENERATE)
        FetchContent_GetProperties(protobuf)  # Assume it's called protobuf.
        if(NOT protobuf_POPULATED)
          message(FATAL "Unable to locate protobuf dependency.")
        endif()
        set(PB_SRC ${protobuf_SOURCE_DIR})

        message(STATUS "  - Will generate: ${OUTPUT_FILE}")

        add_custom_command(
          OUTPUT ${OUTPUT_FILE}
          COMMAND $<TARGET_FILE:protoc>
               --plugin "${PARSED_ARGS_TS_PLUGIN}"
               --ts_proto_opt=esModuleInterop=true,exportCommonSymbols=false,oneof=unions,outputTypeRegistry=true,globalThisPolyfill=true
               --ts_proto_out "${TS_GEN_ROOT_DIR}"
               -I "${PROTO_ROOT_DIR}"
               -I "${PB_SRC}/src"
               "${INPUT_PROTO_FILE}"
          WORKING_DIRECTORY "${PROTO_ROOT_DIR}"
          DEPENDS "${INPUT_PROTO_FILE}"
        )

        add_custom_target(${TS_TARGET}_ts_genfiles_target
                          DEPENDS ${OUTPUT_FILE})
        if (TARGET protoc)
            add_dependencies(${TS_TARGET}_ts_genfiles_target protoc)
        endif()
        add_dependencies(${TS_TARGET}_ts_genfiles_target ${COPY_PROTO_TARGET})
    endif()

    if (PARSED_ARGS_PROTO_BUILD)
        set(GENFILES_TARGET "${TS_TARGET}_ts_genfiles_target" PARENT_SCOPE)
        set(TS_PROTO_ROOT_DIR "${TS_GEN_ROOT_DIR}" PARENT_SCOPE)
        set(OUTPUT_FILE "${OUTPUT_FILE}" PARENT_SCOPE)
    endif()
endfunction()

function(process_proto_file_v2)
    cmake_parse_arguments(
        PARSED_ARGS
        "ENABLE_CC;ENABLE_TS;ENABLE_PY;ENABLE_JAVA;PROTO_GENERATE;PROTO_BUILD"
        "SRC;DEST;TS_PLUGIN;PROTO_GEN_DIR"
        ""  # Relative path to proto (like import statement).
        ${ARGN}
    )
    if(NOT PARSED_ARGS_SRC)
        message(FATAL_ERROR "You must provide a SRC (input file) arg.")
    endif()
    if (NOT PARSED_ARGS_DEST)
        message(FATAL_ERROR "You must provide a DEST argumrnt.")
    endif()

    if (NOT PARSED_ARGS_PROTO_GENERATE AND NOT PARSED_ARGS_PROTO_BUILD)
        set(PARSED_ARGS_PROTO_GENERATE ON)
        set(PARSED_ARGS_PROTO_BUILD ON)
    endif()

    set(PROTO_GEN_FLAG "")
    if (PARSED_ARGS_PROTO_GENERATE)
        set(PROTO_GEN_FLAG "PROTO_GENERATE")
    endif()

    set(PROTO_BUILD_FLAG "")
    if (PARSED_ARGS_PROTO_BUILD)
        set(PROTO_BUILD_FLAG "PROTO_BUILD")
    endif()

    # Scan imports to associate as dependencies.
    message(STATUS "Processing Proto: ${PARSED_ARGS_SRC}")
    file(READ "${PARSED_ARGS_SRC}" proto_file_content)
    string(REPLACE ";" "SEMI-COLON" proto_file_lines "${proto_file_content}")
    string(REPLACE "\n" ";" proto_file_lines "${proto_file_lines}")
    set(proto_package)
    foreach(line in LISTS ${proto_file_lines})
        string(REPLACE "SEMI-COLON" ";" line "${line}")
        string(REGEX MATCH "import *\"([^\"]+)\"" match "${line}")
        if (match)
            set(import_file "${CMAKE_MATCH_1}")
            if (NOT "${import_file}" MATCHES ".*google/protobuf.*")
                list(APPEND dependencies "${import_file}")
            endif()
        endif()

        string(REGEX MATCH "package *([^;]+);" match "${line}")
        if (match)
            set(proto_package "${CMAKE_MATCH_1}")
        endif()
    endforeach()
    message(STATUS "  - Dependencies: ${dependencies}")

    # Check if there are RPC services.
    string(REGEX MATCH "service [a-zA-Z0-9]+ *{" services
           "${proto_file_content}")

    message(STATUS "  - Services: ${services}")

    get_filename_component(proto_file_name "${PARSED_ARGS_SRC}" NAME_WE)
    get_filename_component(rel_path "${PARSED_ARGS_DEST}" DIRECTORY)
    set(out_proto_base_dir "${CMAKE_BINARY_DIR}/gen-proto")
    set(target_copy_proto_file
        "${out_proto_base_dir}/${rel_path}/${proto_file_name}.proto")
    internal_proto_path_to_target(
        PATH "${PARSED_ARGS_DEST}"
        OUT_TARGET PROTO_TARGET)

    file(MAKE_DIRECTORY "${out_proto_base_dir}/${rel_path}")

    list(APPEND java_outer_class_cmd)
    if (PARSED_ARGS_ENABLE_JAVA)
        list(APPEND java_outer_class_cmd ${CMAKE_COMMAND} -E echo)
        list(APPEND java_outer_class_cmd
               "option java_outer_classname = \"${proto_file_name}\"\;"
               ">>"
               ${target_copy_proto_file})
        message(STATUS "Will append options: " ${java_outer_class_cmd})
    endif()

    add_custom_command(
        OUTPUT ${target_copy_proto_file}
        COMMAND ${CMAKE_COMMAND} -E copy
                ${CMAKE_CURRENT_SOURCE_DIR}/${PARSED_ARGS_SRC}
                ${target_copy_proto_file}
        COMMAND ${java_outer_class_cmd}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${PARSED_ARGS_SRC}
        VERBATIM)

    set(current_proto_gen_files_target ${PROTO_TARGET}_copy_genfiles_target)
    add_custom_target(
        ${current_proto_gen_files_target}
        DEPENDS ${target_copy_proto_file})

    foreach(proto_deps IN ITEMS ${dependencies})
        internal_proto_path_to_target(
            PATH "${proto_deps}"
            OUT_TARGET PROTO_TARGET)
        add_dependencies(${current_proto_gen_files_target}
                         ${PROTO_TARGET}_copy_genfiles_target)
    endforeach()

    if (PARSED_ARGS_ENABLE_CC)
        internal_process_cc_proto(
            SRC_BASE_PATH     "${CMAKE_BINARY_DIR}/gen-proto"
            SRC_REL_PATH      "${rel_path}"
            SRC_CORE_NAME     "${proto_file_name}"
            OUTPUT_BASE       "${CMAKE_BINARY_DIR}/gen-cc-proto"
            PROTO_COPY_TARGET "${current_proto_gen_files_target}"
            HAS_SERVICES      "${services}"
            PROTO_DEPS        "${dependencies}"
            PROTO_GEN_DIR     "${PARSED_ARGS_PROTO_GEN_DIR}"
            "${PROTO_GEN_FLAG}"
            "${PROTO_BUILD_FLAG}")
        set(CC_LIB_TARGET ${CC_LIB_TARGET} PARENT_SCOPE)
    endif()

    if (PARSED_ARGS_ENABLE_PY)
        internal_process_py_proto(
            SRC_BASE_PATH     "${CMAKE_BINARY_DIR}/gen-proto"
            SRC_REL_PATH      "${rel_path}"
            SRC_CORE_NAME     "${proto_file_name}"
            OUTPUT_BASE       "${CMAKE_BINARY_DIR}/gen-py-proto"
            PROTO_COPY_TARGET "${current_proto_gen_files_target}"
            PROTO_DEPS        "${dependencies}"
            PROTO_GEN_DIR     "${PARSED_ARGS_PROTO_GEN_DIR}"
            "${PROTO_GEN_FLAG}"
            "${PROTO_BUILD_FLAG}")
        set(PY_PROTO_OUTPUT_FILE ${OUTPUT_FILE} PARENT_SCOPE)
        set(PY_PROTO_TARGET ${GENFILES_TARGET} PARENT_SCOPE)
        set(PY_PROTO_ROOT_DIR ${PY_PROTO_ROOT_DIR} PARENT_SCOPE)
    endif()

    if (PARSED_ARGS_ENABLE_JAVA)
        internal_process_java_proto(
            SRC_BASE_PATH     "${CMAKE_BINARY_DIR}/gen-proto"
            SRC_REL_PATH      "${rel_path}"
            SRC_CORE_NAME     "${proto_file_name}"
            PKG               "${proto_package}"
            OUTPUT_BASE       "${CMAKE_BINARY_DIR}/gen-java-proto"
            PROTO_COPY_TARGET "${current_proto_gen_files_target}"
            PROTO_DEPS        "${dependencies}"
            PROTO_GEN_DIR     "${PARSED_ARGS_PROTO_GEN_DIR}"
            "${PROTO_GEN_FLAG}"
            "${PROTO_BUILD_FLAG}")
        set(JAVA_PROTO_OUTPUT_FILE ${OUTPUT_FILE} PARENT_SCOPE)
        set(JAVA_PROTO_TARGET ${GENFILES_TARGET} PARENT_SCOPE)
        set(JAVA_PROTO_ROOT_DIR ${PY_PROTO_ROOT_DIR} PARENT_SCOPE)
    endif()

    if (PARSED_ARGS_ENABLE_TS)
        if (NOT DEFINED PARSED_ARGS_TS_PLUGIN)
            message(FATAL_ERROR "You must provide a TS_PLUGIN arg.")
        endif()

        internal_process_ts_proto(
            SRC_BASE_PATH     "${CMAKE_BINARY_DIR}/gen-proto"
            SRC_REL_PATH      "${rel_path}"
            SRC_CORE_NAME     "${proto_file_name}"
            OUTPUT_BASE       "${CMAKE_BINARY_DIR}/gen-ts-proto"
            PROTO_COPY_TARGET "${current_proto_gen_files_target}"
            TS_PLUGIN         "${PARSED_ARGS_TS_PLUGIN}"
            PROTO_DEPS        "${dependencies}"
            PROTO_GEN_DIR     "${PARSED_ARGS_PROTO_GEN_DIR}"
            "${PROTO_GEN_FLAG}"
            "${PROTO_BUILD_FLAG}")
        set(TS_PROTO_OUTPUT_FILE ${OUTPUT_FILE} PARENT_SCOPE)
        set(TS_PROTO_TARGET ${GENFILES_TARGET} PARENT_SCOPE)
        set(TS_PROTO_ROOT_DIR ${TS_PROTO_ROOT_DIR} PARENT_SCOPE)
    endif()
endfunction()

function(embed_resource)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "TARGET;BASE_DIR"
        "SOURCES;DEPENDS"
        ""
        ${ARGN}
    )
    if(NOT PARSED_ARGS_TARGET)
        message(FATAL_ERROR "You must provide a TARGET name.")
    endif()
    if(NOT PARSED_ARGS_BASE_DIR)
        message(FATAL_ERROR "You must provide a BASE_DIR.")
    endif()
    if(NOT PARSED_ARGS_SOURCES)
        message(WARNING "Embedding the entire directory.")
    endif()
    message(STATUS "Sources: ${PARSED_ARGS_SOURCES}")

    file(REMOVE "${CMAKE_BINARY_DIR}/embed.py")
    file(APPEND "${CMAKE_BINARY_DIR}/embed.py" "${EMBED_PY_CODE}")

    set(INCLUDE_DIR "${CMAKE_BINARY_DIR}/embed")
    set(OUT_DIR "${INCLUDE_DIR}/${PARSED_ARGS_TARGET}")
    file(MAKE_DIRECTORY ${OUT_DIR})

    add_custom_command(
        OUTPUT "${OUT_DIR}/${PARSED_ARGS_TARGET}.h"
               "${OUT_DIR}/${PARSED_ARGS_TARGET}.cc"
        COMMAND python "${CMAKE_BINARY_DIR}/embed.py"
                "${PARSED_ARGS_TARGET}"
                "${OUT_DIR}"
                "${PARSED_ARGS_BASE_DIR}"
                ${PARSED_ARGS_SOURCES}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        DEPENDS ${PARSED_ARGS_SOURCES} ${PARSED_ARGS_DEPENDS})

    add_library(${PARSED_ARGS_TARGET} STATIC EXCLUDE_FROM_ALL
                "${OUT_DIR}/${PARSED_ARGS_TARGET}.cc")
    target_include_directories(${PARSED_ARGS_TARGET} PUBLIC ${INCLUDE_DIR})
endfunction()

function(anton_plugin)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "SOURCES;DEPENDS"
        ""
        ${ARGN}
    )
    if(NOT PARSED_ARGS_SOURCES)
        message(FATAL_ERROR "No sources provided.")
    endif()

    add_library(${PROJECT_NAME} SHARED ${PARSED_ARGS_SOURCES})
    target_link_libraries(${PROJECT_NAME} PUBLIC anton)

    foreach(dep IN ITEMS ${PARSED_ARGS_DEPENDS})
        target_link_libraries(${PROJECT_NAME} PUBLIC ${dep})
    endforeach()

    target_compile_features(${PROJECT_NAME} PUBLIC cxx_std_17)
    set_target_properties(${PROJECT_NAME} PROPERTIES CXX_STANDARD 17)
endfunction()

