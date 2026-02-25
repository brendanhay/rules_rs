load("@rules_rust//rust:toolchain.bzl", "rust_toolchain")
load("@rules_rust//rust/platform:triple.bzl", _parse_triple = "triple")
load("//rs/experimental/platforms:triples.bzl", "SUPPORTED_EXEC_TRIPLES", "SUPPORTED_TARGET_TRIPLES", "triple_to_constraint_set")
load("//rs/experimental/toolchains:toolchain_utils.bzl", "sanitize_triple", "sanitize_version")

def _channel(version):
    if version.startswith("nightly"):
        return "nightly"
    if version.startswith("beta"):
        return "beta"
    return "stable"

def declare_rustc_toolchains(
        *,
        version,
        edition,
        execs = SUPPORTED_EXEC_TRIPLES,
        targets = SUPPORTED_TARGET_TRIPLES,
        extra_rustc_flags_triples = {}):
    """Declare toolchains for all supported target platforms."""

    version_key = sanitize_version(version)
    channel = _channel(version)

    for triple in execs:
        exec_triple = _parse_triple(triple)
        triple_suffix = exec_triple.system + "_" + exec_triple.arch

        rustc_repo_label = "@rustc_{}_{}//:".format(triple_suffix, version_key)
        cargo_repo_label = "@cargo_{}_{}//:".format(triple_suffix, version_key)
        clippy_repo_label = "@clippy_{}_{}//:".format(triple_suffix, version_key)

        rust_toolchain_name = "{}_{}_{}_rust_toolchain".format(
            exec_triple.system,
            exec_triple.arch,
            version_key,
        )

        rust_std_select = {}
        target_triple_select = {}
        extra_rustc_flags_select = {}
        for target_triple in targets:
            target_key = sanitize_triple(target_triple)
            config_label = "@rules_rs//rs/experimental/platforms/config:{}".format(target_triple)
            rust_std_select[config_label] = "@rust_stdlib_{}_{}//:rust_std-{}".format(target_key, version_key, target_triple)
            target_triple_select[config_label] = target_triple
            extra_rustc_flags_select[config_label] = extra_rustc_flags_triples.get(target_triple, [])

        rust_toolchain(
            name = rust_toolchain_name,
            rust_doc = "{}rustdoc".format(rustc_repo_label),
            rust_std = select(rust_std_select),
            rustc = "{}rustc".format(rustc_repo_label),
            cargo = "{}cargo".format(cargo_repo_label),
            clippy_driver = "{}clippy_driver_bin".format(clippy_repo_label),
            cargo_clippy = "{}cargo_clippy_bin".format(clippy_repo_label),
            # TODO(zbarsky): Enable these once we ship them.
            #llvm_cov = "@llvm//tools:llvm-cov",
            #llvm_profdata = "@llvm//tools:llvm-profdata",
            rustc_lib = "{}rustc_lib".format(rustc_repo_label),
            allocator_library = None,
            global_allocator_library = None,
            binary_ext = select({
                # wasm32-unknown-unknown: cpu:wasm32 + os:none. More specific
                # than the os:none arm, so Bazel picks this entry for wasm32.
                # Bare-metal targets (ARM, RISC-V, x86_64-none) fall through to
                # os:none and get "". Matches rules_rust triple_mappings.bzl:
                # unknown -> ".wasm", none -> "".
                "@rules_rs//rs/experimental/platforms/config:wasm32-unknown-unknown": ".wasm",
                "@platforms//os:none": "",
                "@platforms//os:windows": ".exe",
                "//conditions:default": "",
            }),
            staticlib_ext = select({
                # wasm32-unknown-unknown does not produce a usable static lib.
                # Bare-metal (none) targets use .a. Matches rules_rust:
                # unknown -> "", none -> ".a".
                "@rules_rs//rs/experimental/platforms/config:wasm32-unknown-unknown": "",
                "@platforms//os:none": ".a",
                "@platforms//os:windows": ".lib",
                "//conditions:default": ".a",
            }),
            dylib_ext = select({
                # wasm32 cdylib output uses .wasm. The per-triple config_setting
                # (cpu:wasm32 + os:none) is more specific than os:none alone, so
                # Bazel picks it for wasm32-unknown-unknown while bare-metal
                # targets (ARM, RISC-V, x86_64-none) fall through to os:none.
                # Empty string is falsy in Starlark and breaks determine_lib_name
                # in rules_rust before it reaches the wasm32 cdylib prefix check.
                # Matches rules_rust: unknown -> ".wasm", none -> ".so".
                "@rules_rs//rs/experimental/platforms/config:wasm32-unknown-unknown": ".wasm",
                "@platforms//os:wasi": ".wasm",
                "@platforms//os:none": ".so",
                "@platforms//os:windows": ".dll",
                "@platforms//os:macos": ".dylib",
                "//conditions:default": ".so",
            }),
            stdlib_linkflags = select({
                "@platforms//os:freebsd": ["-lexecinfo", "-lpthread"],
                "@platforms//os:macos": ["-lSystem", "-lresolv"],
                # TODO: windows
                "//conditions:default": [],
            }),
            default_edition = edition,
            exec_triple = triple,
            target_triple = select(target_triple_select),
            extra_rustc_flags = select(extra_rustc_flags_select),
            visibility = ["//visibility:public"],
            tags = ["rust_version={}".format(version)],
        )

        for target_triple in targets:
            target_key = sanitize_triple(target_triple)

            native.toolchain(
                name = "{}_{}_to_{}_{}".format(exec_triple.system, exec_triple.arch, target_key, version_key),
                exec_compatible_with = [
                    "@platforms//os:" + exec_triple.system,
                    "@platforms//cpu:" + exec_triple.arch,
                ],
                target_compatible_with = triple_to_constraint_set(target_triple),
                target_settings = [
                    "@rules_rust//rust/toolchain/channel:" + channel,
                ],
                toolchain = rust_toolchain_name,
                toolchain_type = "@rules_rust//rust:toolchain_type",
                visibility = ["//visibility:public"],
            )
