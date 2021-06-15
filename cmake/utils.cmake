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


function(git_fetch_content name git_repo git_tag)
    set(FETCHCONTENT_QUIET OFF)
    FetchContent_Declare(${name} GIT_REPOSITORY "${git_repo}"
                         GIT_TAG "${git_tag}")
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
        "NAME;URL;VERSION;CMAKE_DIR"
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
    if(NOT ${PARSED_ARGS_NAME}_POPULATED)
        FetchContent_Populate(${PARSED_ARGS_NAME})
        if (EXISTS "${${PARSED_ARGS_NAME}_SOURCE_DIR}/${PARSED_ARGS_CMAKE_DIR}/CMakeLists.txt")
            add_subdirectory(
                ${${PARSED_ARGS_NAME}_SOURCE_DIR}/${PARSED_ARGS_CMAKE_DIR}
                ${${PARSED_ARGS_NAME}_BINARY_DIR})
        endif()
    endif()
    set(${PARSED_ARGS_NAME}_SOURCE_DIR ${${PARSED_ARGS_NAME}_SOURCE_DIR}
        PARENT_SCOPE)
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
        list(APPEND output_files
             "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.cc"
             "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.h")
        list(APPEND proto_srcs
             "${CC_GEN_ROOT_DIR}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.grpc.pb.cc")
        set(GRPC_PARAM --plugin=protoc-gen-grpc=$<TARGET_FILE:grpc_cpp_plugin>)
        set(GRPC_PARAM "${GRPC_PARAM} --grpc_out ${CC_GEN_ROOT_DIR}")

        target_link_libraries(${PARSED_ARGS_TARGET} grpc++_unsecure)
        add_dependencies(${PARSED_ARGS_TARGET} grpc_cpp_plugin)
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

    add_library(${PARSED_ARGS_TARGET} STATIC ${output_files})
    target_include_directories(${PARSED_ARGS_TARGET} PUBLIC ${CC_GEN_ROOT_DIR})
    target_link_libraries(${PARSED_ARGS_TARGET} libprotobuf)
    set_property(TARGET ${PARSED_ARGS_TARGET}
                 PROPERTY POSITION_INDEPENDENT_CODE ON)

    add_dependencies(${PARSED_ARGS_TARGET} protoc)
    add_dependencies(${PARSED_ARGS_TARGET} libprotobuf)
    add_dependencies(${PARSED_ARGS_TARGET}
                     ${PARSED_ARGS_TARGET}_cc_genfiles_target)

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
        "TARGET;SRC;PROTO_DEST;JS_DEST"
        "PROTO_DEPS"
        ${ARGN}
    )
    if(NOT PARSED_ARGS_TARGET)
        message(FATAL_ERROR "You must provide a TARGET name.")
    endif()
    if(NOT PARSED_ARGS_SRC)
        message(FATAL_ERROR "You must provide a SRC (input file) arg.")
    endif()
    if (NOT PARSED_ARGS_PROTO_DEST)
        message(FATAL_ERROR "You must provide a PROTO_DEST argumrnt.")
    endif()
    if (NOT PARSED_ARGS_JS_DEST)
        message(FATAL_ERROR "You must provide a JS_DEST argumrnt.")
    endif()

    process_proto_file(
        SRC ${PARSED_ARGS_SRC}
        DEST ${PARSED_ARGS_PROTO_DEST}
        PROTO_DEPS ${PARSED_ARGS_PROTO_DEPS})
    set(PROTO_ROOT_DIR "${ROOT_DIR}")
    set(PROTO_REL_PATH "${REL_PATH}")
    set(INPUT_PROTO_FILE "${DEST_PROTO_FILE}")
    set(PROTO_CORE_NAME "${CORE_NAME}")
    set(PROTO_DEPENDENCIES "${DEPENDENCIES}")
    set(PROTO_SERVICES "${SERVICES}")
    set(COPY_PROTO_TARGET "${COPY_PROTO_TARGET}")

    set(output_file
        "${PARSED_ARGS_JS_DEST}/${PROTO_REL_PATH}/${PROTO_CORE_NAME}.js")

    message(STATUS "  - Will generate: ${output_file}")

    set(library_path "${PROTO_REL_PATH}/${PROTO_CORE_NAME}")
    set(binary_path "${CMAKE_CURRENT_SOURCE_DIR}/${PARSED_ARGS_JS_DEST}")
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
        DEPENDS ${PARSED_ARGS_SOURCES} ${CMAKE_BINARY_DIR}/embed.py)

    add_library(${PARSED_ARGS_TARGET} STATIC
                "${OUT_DIR}/${PARSED_ARGS_TARGET}.cc")
    target_include_directories(${PARSED_ARGS_TARGET} PUBLIC ${INCLUDE_DIR})

    foreach(dep IN ITEMS ${PARSED_ARGS_DEPENDS})
        add_dependencies(${PARSED_ARGS_TARGET} ${dep})
    endforeach()
endfunction()

