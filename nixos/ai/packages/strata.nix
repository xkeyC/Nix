# Strata Terminal（control 组件）：本地跑 Qwen3.8-Flash-Next 等模型，提供 OpenAI / Anthropic 兼容 API。
#
# 上游 https://github.com/Niko1221/Strata 的 install.sh 会把 control 包解到 ~/.local/share/strata/terminal/<版本>，
# 之后 `strata update` 自己升级。这里改成从 release 固定版本取 control 包放进 store：
#   * 包里自带 python-build-standalone 解释器和 wheel，原样保留不 patchelf（dontFixup），靠 nix-ld 运行。
#   * engine（CUDA 的 C++ 程序 + 运行库）不在这里打包：strata 启动前会按 engine-component.json 校验每个文件的
#     SHA-256，patchelf 后就过不了校验。engine 由 `strata update --no-control` 下到 STRATA_COMPONENTS_DIR。
#   * STRATA_NO_HANDOVER=1：`strata update` 装到组件目录里的新 control 不接管命令，版本只由这里决定。
#   * engine 链接 libcuda.so.1，补上 /run/opengl-driver/lib。
#
# 升级：改 release / version / hash（release 里的 strata-feed.json 列出 control 包的 sha256）。
{ lib
, stdenvNoCC
, fetchurl
, makeWrapper
, componentsDir
}:

stdenvNoCC.mkDerivation rec {
  pname = "strata";
  # control 组件版本；对应 Strata 0.2.7 release。
  version = "0.1.52";
  release = "0.2.7";

  src = fetchurl {
    url = "https://github.com/Niko1221/Strata/releases/download/v${release}/strata-control-${version}-linux-x86_64.tar.gz";
    hash = "sha256-OZ/Mjy0jKy96t9+C2GOHSkuBUBnO2HeiT2ikf/yBEKA=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # 压缩包没有顶层目录。
  unpackPhase = ''
    mkdir source
    tar -xzf $src -C source
    cd source
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/share/strata $out/bin
    cp -a . $out/share/strata
    makeWrapper $out/share/strata/bin/strata $out/bin/strata \
      --set-default STRATA_COMPONENTS_DIR ${componentsDir} \
      --set STRATA_NO_HANDOVER 1 \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib
  '';

  dontFixup = true;

  meta = {
    description = "Strata local inference server (terminal / control component)";
    homepage = "https://github.com/Niko1221/Strata";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "strata";
  };
}
