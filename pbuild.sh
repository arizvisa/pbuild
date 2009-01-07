#!/bin/sh
debug()
{
    if test $DEBUG -gt 0; then
        echo "[debug] $@" 1>&2
    fi
}

info()
{
    echo "[info] $@" 1>&2
}

error()
{
    echo "[error] $@" 1>&2
}

fatal()
{
    echo "[fail] $@" 1>&2
    exit 1
}

# hashGet(hash, key)
# returns hash[key]
hashGet()
{
    hash=$1
    shift
    field=$1
    shift

    if test "$field" == ""; then
        return 1
    fi

    echo "$hash" | while read item; do      # XXX: new process
        key=$( echo "$item" | cut -d ':' -f 1 )
        value=$( echo "$item" | cut -d ':' -f 2- )
        if test "$key" = "$field"; then
            echo "$value"
            exit 1  # XXX: remember we're currently inside a subprocess
        fi
    done

    if test $? -gt 0; then
        return 0
    fi

    # failed
#    error "$field not in $hash"
    return 1
}

hashKeys()
{
    echo "$1" | while read item; do      # XXX: new process
        key=$( echo "$item" | cut -d ':' -f 1 )
        echo $key
    done
    return 0
}

# hashAdd(hash, key, value)
# returns hash with key:value added
hashAdd()
{
    local IFS="\n"
    argh=$1
    shift
    field=$1
    shift
    value=$1
    shift

    item="$field:$value"

    echo "$argh"
    echo "$item"

    return 0
}

# __template(rule, function, dependencies)
# returns a script that resolves "rule" utilizing function
__template()
{
    _rule_=$1
    _directory_=$( echo "$_rule_" | sed 's/[^/\]\+$//' )
    shift
    _function_=$1
    shift
    _dependencies_=$@

    ## template produces the following code
    # count = 0
    # for dep in (_dependencies_):
    #     if dep in $LIST.keys():
    #         res = update_dependency( dep )     # creates file $dep
    #         count += res
    #     elsif dep.age > rule.age:
    #         count += 1
    #
    # if count > 0:
    #     _function_( rule, _dependencies_ )
    #
    # return count

    cat <<EOF
## first do all building
for dep in $_dependencies_; do
    function=\$( hashGet "\$LIST" "\$dep" )
    res=\$?

    debug "isaleaf -> $_rule_: \$dep \$res -> \$function"
    if test \$res -eq 0; then
        ## attempt resolving it w/ a generated build script
        debug ">>>>>>>>>>>> \$dep"
        . "$BUILDDIR/\$dep.$BUILDSUFFIX"
        ## XXX: \$dep is killed at this point
        debug "<<<<<<<<<<<< \$?"
        #touch \$dep
    else
        ## not sure how to resolve it, so treat it as a file
        if test \! -e "\$dep"; then
            fatal "file \$dep not found"
        fi
    fi
done

## check if we've been updated
count=0
for dep in $_dependencies_; do
    test "$_rule_" -ot "\$dep" && count=\$( expr \$count + 1 )
    debug "status -> $_rule_ \$dep \$count"
done

test \$count -gt 0 && res1=1 || res1=0
test \! -e "$_rule_" && res2=1 || res2=0
debug "ruleexist: $_rule_ -> \$count (\$res1, \$res2)"

if test \$res1 -gt 0 -o \$res2 -gt 0; then
    function=\$( hashGet "\$LIST" "$_rule_" )
    info "updating $_rule_ via $function"

    \$function "$_rule_" $_dependencies_

    if test \$? -ne 0; then
        fatal "unable to update $_rule"
    fi
    debug "$_rule_: success"
else
    info "$_rule_ is up to date"
fi

debug "$_rule_: reporting \$count modified files"
return \$count
EOF

    return 0
}

# builds the specified rule
resolve()
{
    rule=$1
    shift
    function=$1
    shift

    LIST=$( hashAdd "$LIST" "$rule" "$function" )

    ## if rule is in a subdirectory
    # FIXME: i'm a dick for testing for '/'s via sed and a strcmp
    __directory=$( echo "$rule" | sed 's/[^/\]\+$//' )

    if test "$__directory" != "$rule" -a ! -d "$BUILDDIR/$__directory"; then
        __directory=$( echo "$rule" | sed 's/[^/\]\+$//' )
        mkdir -p "$BUILDDIR/$__directory"
        info "creating workspace: $__directory"
    fi

    out=$( __template "$rule" "$function" $@ )
    echo "$out" >| "$BUILDDIR/$rule.$BUILDSUFFIX"
    chmod +x "$BUILDDIR/$rule.$BUILDSUFFIX"
}

__help()
{
    echo "Usage: $0 [options] target"
cat <<EOF
build target using the contents of "$FILE"

  -A            make all errors non-fatal
  -x dir        use dir ($BUILDDIR) for storing internal build scripts
  -C dir        change to directory
  -d            display debugging information
  -f file       use specified build file
  -j maxprocs   parallel building
  -q            question mode (1 on failure, 0 on success)

EOF
}

#########################
### main code starts here
# globals
LIST=""

BUILDSUFFIX="sh"    #XXX: this is platform dependant

# options
DEBUG=0
NOBITCH=0
QUESTION=0
JOBS=0
FILE=./pbuild.list
BUILDDIR="./.pbuild"
ROOT=$(pwd)

# parse opts
while getopts AC:df:ij:qhx: opt; do
    case $opt in
        A)
            NOBITCH=1
            ;;

        d)
            DEBUG=1
            ;;

        q)
            QUESTION=1
            fatal "question-mode not supported"
            ;;

        x)
            BUILDDIR=$OPTARG
            ;;

        C)
            chdir $OPTARG       #XXX: chdir needs to be platform independant
            ;;

        f) 
            FILE=$OPTARG
            ;;

        j)
            JOBS=$OPTARG
            fatal "parallel builds not supported"
            ;;

        h)
            __help $0
            exit 0
            ;;
    esac
done
shift $( expr $OPTIND - 1 )

if test $# -lt 1; then
    __help $0
    exit 0
fi

RULE="$1"
shift

if test -e "$BUILDDIR"; then
    if test ! -d "$BUILDDIR"; then
        fatal "$BUILDDIR is not a directory"
    fi
    debug "$BUILDDIR already exists"
else
    info "making build directory: $BUILDDIR"
    mkdir -p "$BUILDDIR"
fi

debug "processing $FILE"
. "$FILE" $@

if test ! -f "$BUILDDIR/$RULE.$BUILDSUFFIX"; then
    fatal "unknown target: $RULE"
fi

# XXX: should dump all targets here and rm them if they're files
debug "building $RULE"
. "$BUILDDIR/$RULE.$BUILDSUFFIX"

info "successfully updated $RULE"
