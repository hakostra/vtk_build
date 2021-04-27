#!/bin/bash

# Build vtk-builder image
docker build -t vtk_build:lastest .

# Copy out resulting wheel
ID=$(docker create vtk_build:lastest)
docker cp $ID:/opt/VTK/vtk/build/dist .
docker rm -v $ID
