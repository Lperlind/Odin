#!/bin/bash
set -eu

mkdir -p build
pushd build
ODIN=../../../odin
COMMON="-collection:tests=../.."

set ERROR_DID_OCCUR=0

set -x

$ODIN test ../test_issue_829.odin  $COMMON -file
$ODIN test ../test_issue_1592.odin $COMMON -file
$ODIN test ../test_issue_2087.odin $COMMON -file
$ODIN build ../test_issue_2113.odin $COMMON -file -debug

set +x
if [ $retVal -ne 0 ]; then
    set ERROR_DID_OCCUR=1
fi

popd
rm -rf build

if [ $retVal -ne 0 ]; then
    exit 1
fi
