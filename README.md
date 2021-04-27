LLVM+OSMesa+VTK build scripts
=============================

The Visualization Toolkit [1] by Kitware is a great package for making complex
3D visualizations.

Several Python projects depend on VTK. One drawback with the official Python
wheels published on PyPi [2] is that they require GPU hardware and an X server
to work. Another drawback is that SMP (threading support) is not enabled.

For high performance post-processing and visualization on remote systems without
GPU's it is possible to build VTK with OSMesa (Offscreen Software Mesa) [3]
support, however, pre-built Python wheels with this is not available.

This repository contain scripts and pre-built VTK wheels with OSMesa and SMP
support for these cases.

Build process
-------------
The build process is inside a Docker build script. A Centos 7 image is taken as
the base image, and LLVM 7 is installed from repos. With this LLVM 7, a more
recent LLVM 12 is compiled. Then, using this LLVM 12, optimizations are turned
on (-march=x86-64-v2) and the compiler builds itself another time (i.e. a manual
two-stage bootstrap process). The reason for building the compiler itself with
optimizations is that the OSMesa `llvmpipe` embed `libllvm` code for usage
during software rendering.

With this optimized compiler and `libllvm`, the OSMesa and VTK libraries are
built. VTK is built against a pre-compiled Intel TBB [4] along with the compiled
OSMesa.

The produced Python wheel is manually manipulated and the relevant shared
libraries for OSMesa and TBB are inserted. This is to produce a self-contained
wheel that do not require special system packages installed.

Missing features
----------------
- There are little or no debugging support due to the compile-time optimizations
- Only a Python 3.8 wheel is built

Warnings
--------
Software rendering is slow. Very slow. There is no hardware rendering support in
this build.

Usage
-----
Make dure you have Docker installed and the required privileges. Run the
provided `build.sh`. The build process will take a long time, be patient.

References
----------
1. https://vtk.org/
2. https://pypi.org/project/vtk/
3. https://docs.mesa3d.org/osmesa.html
4. https://github.com/oneapi-src/onetbb
