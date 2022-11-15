include(FetchContent)
include(CMakeParseArguments)

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

function(process_proto_file)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "SRC;DEST"
        "PROTO_DEPS"
        ${ARGN}
    )
    if(NOT PARSED_ARGS_SRC)
        message(FATAL_ERROR "You must provide a SRC (input file) arg.")
    endif()
    if (NOT PARSED_ARGS_DEST)
        message(FATAL_ERROR "You must provide a DEST argumrnt.")
    endif()

    # Scan imports to associate as dependencies.
    message(STATUS "Processing Proto: ${PARSED_ARGS_SRC}")
    file(READ "${PARSED_ARGS_SRC}" proto_file_content)
    string(REPLACE ";" "SEMI-COLON" proto_file_lines "${proto_file_content}")
    string(REPLACE "\n" ";" proto_file_lines "${proto_file_lines}")
    foreach(line in LISTS ${proto_file_lines})
        string(REGEX MATCH "import *\"([^\"]+)\"" match "${line}")
        if (match)
            list(APPEND dependencies "${CMAKE_MATCH_1}")
        endif()
    endforeach()

    # Check if there are RPC services.
    string(REGEX MATCH "service [a-zA-Z0-9]+ *{" services
           "${proto_file_content}")

    get_filename_component(proto_file_name "${PARSED_ARGS_SRC}" NAME_WE)
    get_filename_component(rel_path "${PARSED_ARGS_DEST}" DIRECTORY)

    set(out_proto_base_dir "${CMAKE_BINARY_DIR}/gen-proto")
    set(copy_proto_file
        "${out_proto_base_dir}/${rel_path}/${proto_file_name}.proto")

    if(NOT TARGET ${PARSED_ARGS_TARGET}_proto_genfiles_target)
        file(MAKE_DIRECTORY "${out_proto_base_dir}/${rel_path}")

        add_custom_command(
            OUTPUT ${copy_proto_file}
            COMMAND ${CMAKE_COMMAND} -E copy
                    ${CMAKE_CURRENT_SOURCE_DIR}/${PARSED_ARGS_SRC}
                    ${copy_proto_file}
            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${PARSED_ARGS_SRC})

        add_custom_target(
            ${PARSED_ARGS_TARGET}_proto_genfiles_target
            DEPENDS ${copy_proto_file})

        foreach(proto_deps IN ITEMS ${PARSED_ARGS_PROTO_DEPS})
            add_dependencies(${PARSED_ARGS_TARGET}_proto_genfiles_target
                             ${proto_deps}_proto_genfiles_target)
        endforeach()
    endif()

    set(ROOT_DIR "${out_proto_base_dir}" PARENT_SCOPE)
    set(REL_PATH "${rel_path}" PARENT_SCOPE)
    set(DEST_PROTO_FILE "${copy_proto_file}" PARENT_SCOPE)
    set(CORE_NAME "${proto_file_name}" PARENT_SCOPE)
    set(DEPENDENCIES "${dependencies}" PARENT_SCOPE)
    set(SERVICES "${services}" PARENT_SCOPE)
    set(COPY_PROTO_TARGET "${PARSED_ARGS_TARGET}_proto_genfiles_target" PARENT_SCOPE)
endfunction()

function(cc_process_proto_file)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "TARGET;SRC;DEST"
        "PROTO_DEPS"
        ${ARGN}
    )
    if(NOT PARSED_ARGS_TARGET)
        message(FATAL_ERROR "You must provide a TARGET name.")
    endif()
    if(NOT PARSED_ARGS_SRC)
        message(FATAL_ERROR "You must provide a SRC (input file) arg.")
    endif()
    if (NOT PARSED_ARGS_DEST)
        message(FATAL_ERROR "You must provide a DEST argumrnt.")
    endif()

    process_proto_file(
        SRC ${PARSED_ARGS_SRC}
        DEST ${PARSED_ARGS_DEST}
        PROTO_DEPS ${PARSED_ARGS_PROTO_DEPS})
    set(PROTO_ROOT_DIR "${ROOT_DIR}")
    set(PROTO_REL_PATH "${REL_PATH}")
    set(INPUT_PROTO_FILE "${DEST_PROTO_FILE}")
    set(PROTO_CORE_NAME "${CORE_NAME}")
    set(PROTO_DEPENDENCIES "${DEPENDENCIES}")
    set(PROTO_SERVICES "${SERVICES}")
    set(COPY_PROTO_TARGET "${COPY_PROTO_TARGET}")

    set(CC_GEN_ROOT_DIR "${CMAKE_BINARY_DIR}/gen-cc-proto")
    file(MAKE_DIRECTORY ${CC_GEN_ROOT_DIR})

    list(APPEND output_files
        "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.pb.cc"
        "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.pb.h")
    list(APPEND proto_srcs
        "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.pb.cc")

    message(STATUS "  - Services: ${PROTO_SERVICES}")
    message(STATUS "  - Dependencies: ${PROTO_DEPENDENCIES}")

    set(GRPC_PARAM "")
    if(PROTO_SERVICES)
        if (TARGET grpc_cpp_plugin)
            list(APPEND output_files
                 "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.cc"
                 "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.h")
            list(APPEND proto_srcs
                 "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.cc")

            set(GRPC_PARAM --plugin=protoc-gen-grpc=$<TARGET_FILE:grpc_cpp_plugin>)
            set(GRPC_PARAM ${GRPC_PARAM} --grpc_out ${CC_GEN_ROOT_DIR})
        else()
            message(WARNING "  No GRPC target, not generated GRPC bindings.")
        endif()
    endif()

    message(STATUS "  - Will generate: ${output_files}")

    add_custom_command(
      OUTPUT ${output_files}
      COMMAND $<TARGET_FILE:protoc>
           --cpp_out "${CC_GEN_ROOT_DIR}"
           -I "${PROTO_ROOT_DIR}"
           ${GRPC_PARAM}
           "${INPUT_PROTO_FILE}"
      WORKING_DIRECTORY "${PROTO_ROOT_DIR}"
      DEPENDS "${INPUT_PROTO_FILE}"
    )
    add_custom_target(
        ${PARSED_ARGS_TARGET}_cc_genfiles_target
        DEPENDS ${output_files})
    add_dependencies(
        ${PARSED_ARGS_TARGET}_cc_genfiles_target
        ${COPY_PROTO_TARGET})

    add_library(${PARSED_ARGS_TARGET} STATIC EXCLUDE_FROM_ALL ${output_files})
    target_include_directories(${PARSED_ARGS_TARGET} PUBLIC ${CC_GEN_ROOT_DIR})
    target_link_libraries(${PARSED_ARGS_TARGET} libprotobuf)
    set_property(TARGET ${PARSED_ARGS_TARGET}
                 PROPERTY POSITION_INDEPENDENT_CODE ON)

    add_dependencies(${PARSED_ARGS_TARGET} protoc)
    add_dependencies(${PARSED_ARGS_TARGET} libprotobuf)
    add_dependencies(${PARSED_ARGS_TARGET}
                     ${PARSED_ARGS_TARGET}_cc_genfiles_target)

    if(PROTO_SERVICES AND TARGET grpc_cpp_plugin)
        target_link_libraries(${PARSED_ARGS_TARGET} grpc++_unsecure)
        add_dependencies(${PARSED_ARGS_TARGET} grpc_cpp_plugin)
    endif()

    foreach(proto_deps IN ITEMS ${PARSED_ARGS_PROTO_DEPS})
        target_link_libraries(${PARSED_ARGS_TARGET} ${proto_deps})
    endforeach()
endfunction()

function(py_process_proto_file)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "TARGET;SRC;DEST"
        ""
        ${ARGN}
    )
    if(NOT PARSED_ARGS_SRC)
        message(FATAL_ERROR "You must provide a SRC (input file) arg.")
    endif()
    if(NOT PARSED_ARGS_TARGET)
        message(FATAL_ERROR "You must provide a TARGET arg.")
    endif()
    if(NOT PARSED_ARGS_DEST)
        message(FATAL_ERROR "You must provide a DEST (Base Directory) arg.")
    endif()

    process_proto_file(
        SRC ${PARSED_ARGS_SRC}
        DEST ${PARSED_ARGS_DEST})
    set(PROTO_ROOT_DIR "${ROOT_DIR}")
    set(PROTO_REL_PATH "${REL_PATH}")
    set(INPUT_PROTO_FILE "${DEST_PROTO_FILE}")
    set(PROTO_CORE_NAME "${CORE_NAME}")
    set(COPY_PROTO_TARGET "${COPY_PROTO_TARGET}")

    set(PY_GEN_ROOT_DIR "${CMAKE_BINARY_DIR}/gen-py-proto")
    set(OUTPUT_FILE
        "${PY_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}_pb2.py")

    file(MAKE_DIRECTORY ${PY_GEN_ROOT_DIR})

    message(STATUS "Reading: ${PARSED_ARGS_SRC}")
    message(STATUS "Will generate: ${OUTPUT_FILE}")

    add_custom_command(
      OUTPUT ${OUTPUT_FILE}
      COMMAND $<TARGET_FILE:protoc>
           --python_out "${PY_GEN_ROOT_DIR}"
           -I "${PROTO_ROOT_DIR}"
           "${INPUT_PROTO_FILE}"
      WORKING_DIRECTORY "${PROTO_ROOT_DIR}"
      DEPENDS "${INPUT_PROTO_FILE}"
    )

    add_custom_target(${PARSED_ARGS_TARGET}_py_genfiles_target
                      DEPENDS ${OUTPUT_FILE})
    add_dependencies(${PARSED_ARGS_TARGET}_py_genfiles_target protoc)
    add_dependencies(${PARSED_ARGS_TARGET}_py_genfiles_target ${COPY_PROTO_TARGET})

    set(GENFILES_TARGET "${PARSED_ARGS_TARGET}_py_genfiles_target" PARENT_SCOPE)
    set(PY_PROTO_ROOT_DIR "${PY_GEN_ROOT_DIR}" PARENT_SCOPE)
    set(OUTPUT_FILE "${OUTPUT_FILE}" PARENT_SCOPE)
endfunction()

function(js_process_proto_file)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "TARGET;SRC;DEST"
        "PROTO_DEPS"
        ${ARGN}
    )
    if(NOT PARSED_ARGS_TARGET)
        message(FATAL_ERROR "You must provide a TARGET name.")
    endif()
    if(NOT PARSED_ARGS_SRC)
        message(FATAL_ERROR "You must provide a SRC (input file) arg.")
    endif()
    if (NOT PARSED_ARGS_DEST)
        message(FATAL_ERROR "You must provide a DEST argumrnt.")
    endif()

    set(JS_DEST "${CMAKE_BINARY_DIR}/gen-js-proto")

    file(MAKE_DIRECTORY ${JS_DEST})

    process_proto_file(
        SRC ${PARSED_ARGS_SRC}
        DEST ${PARSED_ARGS_DEST}
        PROTO_DEPS ${PARSED_ARGS_PROTO_DEPS})
    set(PROTO_ROOT_DIR "${ROOT_DIR}")
    set(PROTO_REL_PATH "${REL_PATH}")
    set(INPUT_PROTO_FILE "${DEST_PROTO_FILE}")
    set(PROTO_CORE_NAME "${CORE_NAME}")
    set(PROTO_DEPENDENCIES "${DEPENDENCIES}")
    set(PROTO_SERVICES "${SERVICES}")
    set(COPY_PROTO_TARGET "${COPY_PROTO_TARGET}")

    set(output_file
        "${JS_DEST}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.js")

    message(STATUS "  - Will generate: ${output_file}")

    set(library_path "${PROTO_REL_PATH}/${PROTO_CORE_NAME}")
    set(binary_path "${JS_DEST}")
    add_custom_command(
      OUTPUT ${output_file}
      COMMAND protoc
           -I "${PROTO_ROOT_DIR}"
           --js_out "import_style=commonjs,binary:${binary_path}"
           "${INPUT_PROTO_FILE}"
      WORKING_DIRECTORY "${PROTO_ROOT_DIR}"
      DEPENDS "${INPUT_PROTO_FILE}"
    )
    add_custom_target(
        ${PARSED_ARGS_TARGET}_js_genfiles_target
        DEPENDS ${output_file})
    add_dependencies(${PARSED_ARGS_TARGET}_js_genfiles_target ${COPY_PROTO_TARGET})

    foreach(proto_deps IN ITEMS ${PARSED_ARGS_PROTO_DEPS})
        add_dependencies(${PARSED_ARGS_TARGET}_js_genfiles_target
                         ${proto_deps}_js_genfiles_target)
    endforeach()

    set(OUTPUT_JS_FILE ${output_file} PARENT_SCOPE)
    set(GENFILE_TARGET ${PARSED_ARGS_TARGET}_js_genfiles_target PARENT_SCOPE)
    set(JS_PROTO_BASE_DIR ${JS_DEST} PARENT_SCOPE)
endfunction()

function(internal_proto_path_to_target path)
    string(REGEX REPLACE "[^a-zA-Z0-9]" "_" TARGET ${path})
    set(PROTO_TARGET "${TARGET}" PARENT_SCOPE)
endfunction()

function(internal_process_cc_proto)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "SRC_BASE_PATH;SRC_REL_PATH;SRC_CORE_NAME;OUTPUT_BASE;PROTO_COPY_TARGET;HAS_SERVICES"
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
    set(CC_GEN_ROOT_DIR "${PARSED_ARGS_OUTPUT_BASE}")

    internal_proto_path_to_target("${PROTO_REL_PATH}/${PROTO_CORE_NAME}.proto")
    set(CC_LIB_TARGET ${PROTO_TARGET})

    file(MAKE_DIRECTORY ${CC_GEN_ROOT_DIR})

    list(APPEND output_files
        "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.pb.cc"
        "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.pb.h")
    list(APPEND proto_srcs
        "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.pb.cc")

    set(GRPC_PARAM "")
    if(PROTO_SERVICES)
        if (TARGET grpc_cpp_plugin)
            list(APPEND output_files
                 "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.cc"
                 "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.h")
            list(APPEND proto_srcs
                 "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.cc")

            set(GRPC_PARAM --plugin=protoc-gen-grpc=$<TARGET_FILE:grpc_cpp_plugin>)
            set(GRPC_PARAM ${GRPC_PARAM} --grpc_out ${CC_GEN_ROOT_DIR})
        else()
            message(WARNING "  No GRPC plugin target, did not generate GRPC bindings.")
        endif()
    endif()

    message(STATUS "  - Will generate: ${output_files}")

    add_custom_command(
      OUTPUT ${output_files}
      COMMAND $<TARGET_FILE:protoc>
           --cpp_out "${CC_GEN_ROOT_DIR}"
           -I "${PROTO_ROOT_DIR}"
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

    add_library(${CC_LIB_TARGET} STATIC EXCLUDE_FROM_ALL ${output_files})
    target_include_directories(${CC_LIB_TARGET} PUBLIC ${CC_GEN_ROOT_DIR})
    target_link_libraries(${CC_LIB_TARGET} libprotobuf)

    add_dependencies(${CC_LIB_TARGET} protoc)
    add_dependencies(${CC_LIB_TARGET} libprotobuf)
    add_dependencies(${CC_LIB_TARGET} ${CC_LIB_TARGET}_cc_genfiles_target)

    if(PROTO_SERVICES AND TARGET grpc_cpp_plugin)
        target_link_libraries(${CC_LIB_TARGET} grpc++_unsecure)
        add_dependencies(${CC_LIB_TARGET} grpc_cpp_plugin)
    endif()

    foreach(proto_deps IN ITEMS ${PARSED_ARGS_PROTO_DEPS})
        internal_proto_path_to_target(${proto_deps})
        target_link_libraries(${CC_LIB_TARGET} ${PROTO_TARGET})
    endforeach()

    set(CC_LIB_TARGET ${CC_LIB_TARGET} PARENT_SCOPE)
endfunction()

function(internal_process_py_proto)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "SRC_BASE_PATH;SRC_REL_PATH;SRC_CORE_NAME;OUTPUT_BASE;PROTO_COPY_TARGET"
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
    set(PY_GEN_ROOT_DIR "${PARSED_ARGS_OUTPUT_BASE}")
    set(OUTPUT_FILE
        "${PY_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}_pb2.py")

    internal_proto_path_to_target("${PROTO_REL_PATH}/${PROTO_CORE_NAME}.proto")
    set(PY_TARGET ${PROTO_TARGET})

    file(MAKE_DIRECTORY ${PY_GEN_ROOT_DIR})

    message(STATUS "  - Will generate: ${OUTPUT_FILE}")

    add_custom_command(
      OUTPUT ${OUTPUT_FILE}
      COMMAND $<TARGET_FILE:protoc>
           --python_out "${PY_GEN_ROOT_DIR}"
           -I "${PROTO_ROOT_DIR}"
           "${INPUT_PROTO_FILE}"
      WORKING_DIRECTORY "${PROTO_ROOT_DIR}"
      DEPENDS "${INPUT_PROTO_FILE}"
    )

    add_custom_target(${PY_TARGET}_py_genfiles_target
                      DEPENDS ${OUTPUT_FILE})
    add_dependencies(${PY_TARGET}_py_genfiles_target protoc)
    add_dependencies(${PY_TARGET}_py_genfiles_target ${COPY_PROTO_TARGET})

    set(GENFILES_TARGET "${PY_TARGET}_py_genfiles_target" PARENT_SCOPE)
    set(PY_PROTO_ROOT_DIR "${PY_GEN_ROOT_DIR}" PARENT_SCOPE)
    set(OUTPUT_FILE "${OUTPUT_FILE}" PARENT_SCOPE)
endfunction()

function(internal_process_ts_proto)
    cmake_parse_arguments(
        PARSED_ARGS
        ""
        "SRC_BASE_PATH;SRC_REL_PATH;SRC_CORE_NAME;OUTPUT_BASE;PROTO_COPY_TARGET;TS_PLUGIN"
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
    set(TS_GEN_ROOT_DIR "${PARSED_ARGS_OUTPUT_BASE}")
    set(OUTPUT_FILE
        "${TS_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.ts")

    internal_proto_path_to_target("${PROTO_REL_PATH}/${PROTO_CORE_NAME}.proto")
    set(TS_TARGET ${PROTO_TARGET})

    file(MAKE_DIRECTORY ${TS_GEN_ROOT_DIR})

    message(STATUS "  - Will generate: ${OUTPUT_FILE}")

    add_custom_command(
      OUTPUT ${OUTPUT_FILE}
      COMMAND $<TARGET_FILE:protoc>
           --plugin "${PARSED_ARGS_TS_PLUGIN}"
           --ts_proto_opt=esModuleInterop=true,exportCommonSymbols=false
           --ts_proto_out "${TS_GEN_ROOT_DIR}"
           -I "${PROTO_ROOT_DIR}"
           "${INPUT_PROTO_FILE}"
      WORKING_DIRECTORY "${PROTO_ROOT_DIR}"
      DEPENDS "${INPUT_PROTO_FILE}"
    )

    add_custom_target(${TS_TARGET}_ts_genfiles_target
                      DEPENDS ${OUTPUT_FILE})
    add_dependencies(${TS_TARGET}_ts_genfiles_target protoc)
    add_dependencies(${TS_TARGET}_ts_genfiles_target ${COPY_PROTO_TARGET})

    set(GENFILES_TARGET "${TS_TARGET}_ts_genfiles_target" PARENT_SCOPE)
    set(TS_PROTO_ROOT_DIR "${TS_GEN_ROOT_DIR}" PARENT_SCOPE)
    set(OUTPUT_FILE "${OUTPUT_FILE}" PARENT_SCOPE)
endfunction()

function(process_proto_file_v2)
    cmake_parse_arguments(
        PARSED_ARGS
        "ENABLE_CC;ENABLE_TS;ENABLE_PY"
        "SRC;DEST;TS_PLUGIN"
        ""  # Relative path to proto (like import statement).
        ${ARGN}
    )
    if(NOT PARSED_ARGS_SRC)
        message(FATAL_ERROR "You must provide a SRC (input file) arg.")
    endif()
    if (NOT PARSED_ARGS_DEST)
        message(FATAL_ERROR "You must provide a DEST argumrnt.")
    endif()

    # Scan imports to associate as dependencies.
    message(STATUS "Processing Proto: ${PARSED_ARGS_SRC}")
    file(READ "${PARSED_ARGS_SRC}" proto_file_content)
    string(REPLACE ";" "SEMI-COLON" proto_file_lines "${proto_file_content}")
    string(REPLACE "\n" ";" proto_file_lines "${proto_file_lines}")
    foreach(line in LISTS ${proto_file_lines})
        string(REGEX MATCH "import *\"([^\"]+)\"" match "${line}")
        if (match)
            list(APPEND dependencies "${CMAKE_MATCH_1}")
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
    internal_proto_path_to_target("${PARSED_ARGS_DEST}") # Result: PROTO_TARGET


    file(MAKE_DIRECTORY "${out_proto_base_dir}/${rel_path}")

    add_custom_command(
        OUTPUT ${target_copy_proto_file}
        COMMAND ${CMAKE_COMMAND} -E copy
                ${CMAKE_CURRENT_SOURCE_DIR}/${PARSED_ARGS_SRC}
                ${target_copy_proto_file}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${PARSED_ARGS_SRC})

    set(current_proto_gen_files_target ${PROTO_TARGET}_copy_genfiles_target)
    add_custom_target(
        ${current_proto_gen_files_target}
        DEPENDS ${target_copy_proto_file})

    foreach(proto_deps IN ITEMS ${dependencies})
        internal_proto_path_to_target("${proto_deps}")
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
            PROTO_DEPS        ${dependencies})
        set(CC_LIB_TARGET ${CC_LIB_TARGET} PARENT_SCOPE)
    endif()

    if (PARSED_ARGS_ENABLE_PY)
        internal_process_py_proto(
            SRC_BASE_PATH     "${CMAKE_BINARY_DIR}/gen-proto"
            SRC_REL_PATH      "${rel_path}"
            SRC_CORE_NAME     "${proto_file_name}"
            OUTPUT_BASE       "${CMAKE_BINARY_DIR}/gen-py-proto"
            PROTO_COPY_TARGET "${current_proto_gen_files_target}"
            PROTO_DEPS        ${dependencies})
        set(PY_PROTO_OUTPUT_FILE ${OUTPUT_FILE} PARENT_SCOPE)
        set(PY_PROTO_TARGET ${GENFILES_TARGET} PARENT_SCOPE)
        set(PY_PROTO_ROOT_DIR ${PY_PROTO_ROOT_DIR} PARENT_SCOPE)
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
            PROTO_DEPS        ${dependencies})
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

