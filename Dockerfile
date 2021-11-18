# ---------------------------------------------------------------------------- #
# Image to build LLVM, OSMesa and VTK
# ---------------------------------------------------------------------------- #
FROM centos:7 AS vtk_build
LABEL maintainer="Håkon Strandenes <h.strandenes@km-turbulenz.no>"
LABEL description="LLVM+OSMesa+VTK builder"

# Note: "yum check-update" return code 100 if there are packages to be updated,
# hence the ";" instead of "&&"
RUN yum check-update ; \
    yum -y install epel-release && \
    yum -y update && \
    yum -y install wget unzip centos-release-scl patchelf zlib-devel bison flex binutils-devel patch && \
    yum -y install rh-python38 rh-python38-python-devel \
                   llvm-toolset-7.0 llvm-toolset-7.0-clang \
                   rh-git218 && \
    yum clean all

# Python 3.8 package installation
#
# Wheel is used to build and manipulate Python wheels
# Auditwheel is a useful utility to manipulate Python wheels
# Meson is the build system of OSMesa
# Mako is a dependency of Meson that is not installed automatically
RUN source scl_source enable rh-python38 && \
    mkdir -p /opt/python38 && \
    cd /opt/python38 && \
    python -m venv . && \
    source bin/activate && \
    pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --upgrade setuptools && \
    pip install --no-cache-dir wheel auditwheel meson mako && \
    pip freeze --all > requirements.txt

# Fetch and install updated CMake in /usr/local
ARG CMAKE_VER="3.20.1"
ARG CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v3.20.1/cmake-3.20.1-linux-x86_64.tar.gz"
RUN mkdir /tmp/cmake-install && \
    cd /tmp/cmake-install && \
    wget --no-verbose $CMAKE_URL && \
    tar -xf cmake-${CMAKE_VER}-linux-x86_64.tar.gz -C /usr/local --strip-components=1 && \
    cd / && \
    rm -rf /tmp/cmake-install

# Fetch and install updated Ninja-build in /usr/local
ARG NINJA_URL="https://github.com/ninja-build/ninja/releases/download/v1.10.2/ninja-linux.zip"
RUN mkdir /tmp/ninja-install && \
    cd /tmp/ninja-install && \
    wget --no-verbose $NINJA_URL && \
    unzip ninja-linux.zip -d /usr/local/bin && \
    cd / && \
    rm -rf /tmp/ninja-install

# LLVM + Clang compilation using LLVM-7 from Centos SCL
ARG LLVM_VER="12.0.1"
ARG LLVM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-12.0.1/llvm-project-12.0.1.src.tar.xz"
RUN set -o pipefail && \
    source scl_source enable llvm-toolset-7.0 && \
    source scl_source enable rh-python38 && \
    mkdir -p /opt/llvm-build && \
    cd /opt/llvm-build && \
    wget --no-verbose $LLVM_URL && \
    tar -xf llvm-project-${LLVM_VER}.src.tar.xz && \
    cd llvm-project-${LLVM_VER}.src && \
    mkdir build && \
    cd build && \
    cmake -GNinja \
        -DLLVM_ENABLE_PROJECTS="clang;lld" \
        -DCMAKE_BUILD_TYPE="Release" \
        -DCMAKE_INSTALL_PREFIX="/usr/local" \
        -DLLVM_TARGETS_TO_BUILD=X86 \
        -DLLVM_ENABLE_RTTI=ON \
        -DLLVM_INSTALL_UTILS=ON \
        -DLLVM_ENABLE_TERMINFO=OFF \
        -DLLVM_ENABLE_ZLIB=OFF \
        ../llvm 2>&1 | tee cmake.log && \
    ninja 2>&1 | tee ninja.log && \
    ninja install 2>&1 | tee ninja_install.log

# CPU architecture for optimizations
ARG CPU_ARCH="x86-64-v2"
ENV CFLAGS="-march=${CPU_ARCH}"
ENV CXXFLAGS="-march=${CPU_ARCH}"

# LLVM stage 2 compilation - building LLVM and libLLVM with x86-64-v2
RUN set -o pipefail && \
    source scl_source enable rh-python38 && \
    cd /opt/llvm-build/llvm-project-${LLVM_VER}.src/ && \
    mkdir build-stage2 && \
    cd build-stage2 && \
    cmake -GNinja \
        -DLLVM_ENABLE_PROJECTS="clang;lld" \
        -DCMAKE_BUILD_TYPE="Release" \
        -DCMAKE_INSTALL_PREFIX="/usr/local" \
        -DLLVM_TARGETS_TO_BUILD=X86 \
        -DLLVM_ENABLE_RTTI=ON \
        -DLLVM_INSTALL_UTILS=ON \
        -DLLVM_ENABLE_TERMINFO=OFF \
        -DLLVM_ENABLE_ZLIB=OFF \
        ../llvm 2>&1 | tee cmake.log && \
    ninja 2>&1 | tee ninja.log && \
    ninja install 2>&1 | tee ninja_install.log

# Download mesa library
ARG MESA_VER="21.3.0"
ARG MESA_URL="https://archive.mesa3d.org/mesa-21.3.0.tar.xz"
RUN mkdir -p /opt/mesa && \
    cd /opt/mesa && \
    wget --no-verbose $MESA_URL && \
    tar -xf mesa-${MESA_VER}.tar.xz

# Build OSMesa
RUN set -o pipefail && \
    source scl_source enable rh-python38 && \
    source /opt/python38/bin/activate && \
    cd /opt/mesa/mesa-${MESA_VER} && \
    mkdir build && \
    meson build \
        -Dbuildtype=release \
        -Dosmesa=true \
        -Dgallium-drivers=swrast \
        -Dglx=disabled \
        -Ddri3=disabled \
        -Degl=disabled \
        -Ddri-drivers=[] \
        -Dvulkan-drivers=[] \
        -Dplatforms= \
        -Dshared-llvm=false \
        -Dshared-glapi=disabled \
        -Dlibunwind=disabled \
        -Dprefix=$PWD/build/install 2>&1 | tee cmake.log && \
    ninja -C build install 2>&1 | tee ninja.log

ENV OSMESA_ROOT="/opt/mesa/mesa-${MESA_VER}/build/install"

# Intel Thread Building Blocks (TBB)
# Use last 2020-release:
# https://gitlab.kitware.com/vtk/vtk/-/issues/18107
ARG TBB_VER="2020.3"
ARG TBB_URL="https://github.com/oneapi-src/oneTBB/releases/download/v2020.3/tbb-2020.3-lin.tgz"
RUN mkdir /opt/TBB && \
    cd /opt/TBB && \
    wget --no-verbose $TBB_URL && \
    tar -xf tbb-${TBB_VER}-lin.tgz
ENV TBB_ROOT="/opt/TBB/tbb"

# Patch TBB to compile with LLVM - maybe a bit dirty, but works...
COPY TBBConfig.cmake.diff /opt/TBB/tbb/
RUN cd /opt/TBB/tbb/ && \
    patch -u cmake/TBBConfig.cmake -i TBBConfig.cmake.diff

# VTK compilation
ARG VTK_BRANCH="master"
ARG VTK_COMMIT="1b4c0e94"
ARG VTK_VER="9.1.20211118"
ARG VTK_URL="https://gitlab.kitware.com/vtk/vtk.git"

RUN source scl_source enable rh-git218 && \
    mkdir -p /opt/VTK && \
    cd /opt/VTK && \
    git clone -b $VTK_BRANCH --single-branch $VTK_URL && \
    cd vtk && \
    git checkout $VTK_COMMIT

RUN set -o pipefail && \
    source scl_source enable rh-python38 && \
    source /opt/python38/bin/activate && \
    cd /opt/VTK/vtk && \
    mkdir build && cd build && \
    export LDFLAGS="-fuse-ld=lld" && \
    cmake -GNinja \
        -DVTK_BUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DVTK_WHEEL_BUILD=ON \
        -DVTK_WRAP_PYTHON=ON \
        -DVTK_PYTHON_VERSION=3 \
        -DVTK_OPENGL_HAS_OSMESA=True \
        -DVTK_USE_X=False \
        -DVTK_DEFAULT_RENDER_WINDOW_OFFSCREEN=ON \
        -DVTK_SMP_IMPLEMENTATION_TYPE=TBB \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
        ../ 2>&1 | tee cmake.log && \
    ninja 2>&1 | tee ninja.log && \
    python setup.py bdist_wheel 2>&1 | tee setup_py.log

# Manually 'patch' produced wheel, adding OSMesa and TBB shared libraries
ARG VTK_PYVER="${VTK_VER}.dev0"
RUN source scl_source enable rh-python38 && \
    source /opt/python38/bin/activate && \
    mkdir /tmp/patch-vtkwheel && \
    cd /tmp/patch-vtkwheel && \
    wheel unpack /opt/VTK/vtk/build/dist/vtk-${VTK_PYVER}-cp38-cp38-linux_x86_64.whl && \
    cp $OSMESA_ROOT/lib64/libOSMesa.so.8.0.0 vtk-${VTK_PYVER}/vtkmodules/libOSMesa.so.8 && \
    #cp $OSMESA_ROOT/lib64/libglapi.so.0.0.0 vtk-${VTK_PYVER}/vtkmodules/libglapi.so.0 && \
    #cp $OSMESA_ROOT/lib64/libswrAVX2.so.0.0.0 vtk-${VTK_PYVER}/vtkmodules/libswrAVX2.so && \
    #cp $OSMESA_ROOT/lib64/libswrAVX.so.0.0.0 vtk-${VTK_PYVER}/vtkmodules/libswrAVX.so && \
    patchelf --set-rpath "\$ORIGIN" vtk-${VTK_PYVER}/vtkmodules/libOSMesa.so.8 && \
    #patchelf --set-rpath "\$ORIGIN" vtk-${VTK_PYVER}/vtkmodules/libglapi.so.0 && \
    cp /opt/mesa/mesa-${MESA_VER}/docs/license.rst vtk-${VTK_PYVER}/vtk-${VTK_PYVER}.dist-info/LICENSE-OSMesa.rst && \
    cp $TBB_ROOT/lib/intel64/gcc4.8/libtbb* vtk-${VTK_PYVER}/vtkmodules/ && \
    cp $TBB_ROOT/LICENSE vtk-${VTK_PYVER}/vtk-${VTK_PYVER}.dist-info/LICENSE-TBB && \
    wheel pack --dest-dir /opt/VTK/vtk/build/dist/ vtk-${VTK_PYVER} && \
    cd / && \
    rm -rf /tmp/patch-vtkwheel

# Install wheel (for testing)
RUN source scl_source enable rh-python38 && \
    source /opt/python38/bin/activate && \
    pip install /opt/VTK/vtk/build/dist/vtk-${VTK_PYVER}-cp38-cp38-linux_x86_64.whl

# Add files
COPY env.sh /opt/
