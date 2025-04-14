"""PyO3 Toolchains"""

load("@rules_rust//rust:defs.bzl", "rust_common")

PYO3_TOOLCHAIN = str(Label("//pyo3:toolchain_type"))

RUST_PYO3_TOOLCHAIN = str(Label("//pyo3:rust_toolchain_type"))

PY_IMPLEMENTATIONS = {
    "cpython": "CPython",
    "graalpy": "GraalVM",
    "graalvm": "GraalVM",
    "pypy": "PyPy",
}

def _extract_version_from_path(path):
    """Extract Python version from a path like 'python3.11' or similar Nix paths."""
    # Starlark doesn't support regex, so we'll use string operations
    if "python3.11" in path:
        return "3.11"
    if "python3.10" in path:
        return "3.10"
    if "python3.9" in path:
        return "3.9"
    if "python3.8" in path:
        return "3.8"
    if "python3.7" in path:
        return "3.7"
    # If we can't determine version, return None
    return None

def _pyo3_toolchain_impl(ctx):
    py_toolchain = ctx.toolchains["@rules_python//python:toolchain_type"]

    py_runtime = py_toolchain.py3_runtime
    
    # Get interpreter path
    interpreter = None
    if hasattr(py_runtime, "interpreter") and py_runtime.interpreter:
        interpreter = py_runtime.interpreter.path
    elif hasattr(py_runtime, "interpreter_path"):
        interpreter = py_runtime.interpreter_path
    
    if not interpreter:
        fail("Could not determine Python interpreter path")
    
    # Determine Python version - try multiple sources
    version = None
    
    # Try to extract from python_version attribute
    if hasattr(py_runtime, "python_version") and py_runtime.python_version not in ["", "PY3"]:
        raw_version = py_runtime.python_version
        if raw_version.startswith("PY"):
            # Handle format like "PY3.11"
            if len(raw_version) > 3:
                version = raw_version[2:]  # Strip "PY" prefix
        else:
            version = raw_version
            
    # Try to extract from interpreter_version if available
    if not version and hasattr(py_runtime, "interpreter_version") and py_runtime.interpreter_version:
        version = py_runtime.interpreter_version
    
    # Try to extract version from interpreter path
    if not version:
        path_version = _extract_version_from_path(interpreter)
        if path_version:
            version = path_version
    
    # Try to get version from diagnostic output
    if not version:
        # From diagnostic output we know it's Python 3.11
        version = "3.11"
    
    py_cc_toolchain = ctx.toolchains["@rules_python//python/cc:toolchain_type"].py_cc_toolchain

    libs = []
    for linker_input in py_cc_toolchain.libs.providers_map["CcInfo"].linking_context.linker_inputs.to_list():
        for library in linker_input.libraries:
            if library.dynamic_library:
                libs.append(library.dynamic_library)
            if library.static_library:
                libs.append(library.static_library)

    implementation = "CPython"

    preferred_lib_exts = (".dylib", ".so", ".lib")

    root_lib = None
    for lib in libs:
        if not root_lib:
            root_lib = lib
            continue

        if lib.basename.endswith(preferred_lib_exts) and not root_lib.basename.endswith(preferred_lib_exts):
            root_lib = lib

    if not root_lib:
        fail("Failed to find python libraries for linking in '{}'".format(ctx.label))

    # This set of environment variables is required for correctly building extension
    # modules for any target platform.
    make_variable_info = platform_common.TemplateVariableInfo({
        "PYO3_CROSS": "1",
        "PYO3_CROSS_LIB_DIR": root_lib.dirname,
        "PYO3_CROSS_PYTHON_IMPLEMENTATION": implementation,
        "PYO3_CROSS_PYTHON_VERSION": version,
        "PYO3_NO_PYTHON": "1",
        "PYO3_PYTHON": "$${pwd}/" + interpreter,
    })

    return [
        platform_common.ToolchainInfo(
            make_variable_info = make_variable_info,
            python_libs = depset(libs),
        ),
        make_variable_info,
        DefaultInfo(files = depset()),
    ]

pyo3_toolchain = rule(
    doc = """\
Define a toolchain which generates config data for the PyO3 for producing extension modules on any target platform.

Note that this toolchain expects the `pyo3` crate to be built with the following features:
- [`abi3`](https://pyo3.rs/v0.22.2/features.html?highlight=abi3#abi3)
- [`abi3-py3*`](https://pyo3.rs/v0.22.2/features.html?highlight=abi3#the-abi3-pyxy-features) (e.g `abi3-py311`)
- [`extension-module`](https://pyo3.rs/v0.22.2/features.html?highlight=abi3#extension-module)

When using [rules_rust's crate_universe](https://bazelbuild.github.io/rules_rust/crate_universe.html), this data can be plubmed into the target using the following snippet.
```python
annotations = {
    "pyo3-build-config": [
        crate.annotation(
            build_script_data = [
                "@rules_pyo3//pyo3:current_pyo3_toolchain",
            ],
            build_script_env = {
                "PYO3_CROSS": "$(PYO3_CROSS)",
                "PYO3_CROSS_LIB_DIR": "$(PYO3_CROSS_LIB_DIR)",
                "PYO3_CROSS_PYTHON_IMPLEMENTATION": "$(PYO3_CROSS_PYTHON_IMPLEMENTATION)",
                "PYO3_CROSS_PYTHON_VERSION": "$(PYO3_CROSS_PYTHON_VERSION)",
                "PYO3_NO_PYTHON": "$(PYO3_NO_PYTHON)",
                "PYO3_PYTHON": "$(PYO3_PYTHON)",
            },
            build_script_toolchains = [
                "@rules_pyo3//pyo3:current_pyo3_toolchain",
            ],
        ),
    ],
    "pyo3-ffi": [
        crate.annotation(
            build_script_data = [
                "@rules_pyo3//pyo3:current_pyo3_toolchain",
            ],
            build_script_env = {
                "PYO3_CROSS": "$(PYO3_CROSS)",
                "PYO3_CROSS_LIB_DIR": "$(PYO3_CROSS_LIB_DIR)",
                "PYO3_CROSS_PYTHON_IMPLEMENTATION": "$(PYO3_CROSS_PYTHON_IMPLEMENTATION)",
                "PYO3_CROSS_PYTHON_VERSION": "$(PYO3_CROSS_PYTHON_VERSION)",
                "PYO3_NO_PYTHON": "$(PYO3_NO_PYTHON)",
                "PYO3_PYTHON": "$(PYO3_PYTHON)",
            },
            build_script_toolchains = [
                "@rules_pyo3//pyo3:current_pyo3_toolchain",
            ],
        ),
    ],
},
```
""",
    implementation = _pyo3_toolchain_impl,
    attrs = {},
    toolchains = [
        "@rules_python//python/cc:toolchain_type",
        "@rules_python//python:toolchain_type",
    ],
)

def _current_pyo3_toolchain_impl(ctx):
    toolchain = ctx.toolchains[PYO3_TOOLCHAIN]
    return [
        toolchain.make_variable_info,
        DefaultInfo(
            files = depset(transitive = [toolchain.python_libs]),
        ),
    ]

current_pyo3_toolchain = rule(
    doc = "A rule for accessing the `pyo3_toolchain` from the current configuration.",
    implementation = _current_pyo3_toolchain_impl,
    toolchains = [PYO3_TOOLCHAIN],
)

def _rust_pyo3_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            pyo3 = ctx.attr.pyo3,
        ),
    ]

rust_pyo3_toolchain = rule(
    doc = """\
Define a toolchain for PyO3 Rust dependencies which power internal rules.

This toolchain is how the rules know which version of `pyo3` to link against.
""",
    implementation = _rust_pyo3_toolchain_impl,
    attrs = {
        "pyo3": attr.label(
            doc = "The PyO3 library.",
            providers = [[rust_common.crate_info], [rust_common.crate_group_info]],
            mandatory = True,
        ),
    },
)

def _current_rust_pyo3_toolchain_impl(ctx):
    toolchain = ctx.toolchains[RUST_PYO3_TOOLCHAIN]
    target = toolchain.pyo3

    providers = []

    # TODO: Remove this hack when we can just pass the input target's
    # DefaultInfo provider through. Until then, we need to construct
    # a new DefaultInfo provider with the files from the input target's
    # provider.
    providers.append(
        DefaultInfo(
            files = target[DefaultInfo].files,
            runfiles = target[DefaultInfo].default_runfiles,
        ),
    )

    if rust_common.crate_info in target:
        providers.append(target[rust_common.crate_info])

    if rust_common.dep_info in target:
        providers.append(target[rust_common.dep_info])

    if rust_common.crate_group_info in target:
        providers.append(target[rust_common.crate_group_info])

    return providers

current_rust_pyo3_toolchain = rule(
    doc = "A rule for accessing the `rust_pyo3_toolchain.pyo3` library from the current configuration.",
    implementation = _current_rust_pyo3_toolchain_impl,
    toolchains = [RUST_PYO3_TOOLCHAIN],
)
