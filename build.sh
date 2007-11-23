#!/bin/dash
debug()
{
    if $( test $DEBUG -gt 0 ); then
        echo "[debug] $@" 1>&2
    fi
}

info()
{
    echo "[info] $@" 1>&2
}

error()
{
    echo "[fail] $@" 1>&2
    exit
}

fatal()
{
    echo "[fatal] $@" 1>&2
    exit
}

# _hashGet(hash, key)
# returns hash[key]
_hashGet()
{
    hash=$1
    shift
    field=$1
    shift

    echo "$hash" | while read item; do      # XXX: new process
        key=$( echo "$item" | cut -d ':' -f 1 )
        value=$( echo "$item" | cut -d ':' -f 2- )
        if $( test "$key" = "$field" ); then
            echo "$value"
            exit 1  # XXX: remember we're spawning another process
        fi
    done

    if $( test $? -gt 0 ); then
        return 0
    fi

    # failed
#    error "$field not in $hash"
    return 1
}

_hashKeys()
{
    echo "$1" | while read item; do      # XXX: new process
        key=$( echo "$item" | cut -d ':' -f 1 )
        echo $key
    done
    return 0
}

# _hashAdd(hash, key, value)
# returns hash with key:value added
_hashAdd()
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

# _template(rule, function, dependencies)
# returns a script that resolves "rule" utilizing function
_template()
{
    _rule_=$1
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
count=0
for dep in $_dependencies_; do
    function=\$( _hashGet "\$LIST" "\$dep" )

    if \$( test \$? -gt 0 ); then
        # not sure how to resolve it, so treat it as a file
        if \$( test ! -e "\$dep" ); then
            error "file \$dep not found"
        fi

        if \$( test "\$dep" -nt "$_rule_"  ); then
            debug "\$dep newer than $_rule_"
            count=\$( expr \$count + 1 )
        else
            debug "\$dep is ok"
        fi
    else
        # attempt resolving it w/ a generated build script
        debug "resolving \$dep with \$dep.$BUILDSUFFIX"
        . "$BUILDDIR/\$dep.$BUILDSUFFIX"
        count=\$( expr $count + \$? )
    fi
done

if \$( test \$count -gt 0 ); then
    info "updating $_rule_"
    function=\$( _hashGet "\$LIST" "$_rule_" )
    \$function $_rule_ $_dependencies_
else
    info "$_rule_ is up to date"
fi

debug "$_rule_ returned \$count modified files"
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

    LIST=$( _hashAdd "$LIST" "$rule" "$function" )

    out=$( _template "$rule" "$function" $@ )
    echo "$out" > "$BUILDDIR/$rule.$BUILDSUFFIX"
    chmod +x "$BUILDDIR/$rule.$BUILDSUFFIX"
}

_help()
{
    echo "Usage: $0 target [args...]"
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
FILE=./build.list
BUILDDIR="./.build"

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
            _help $0
            exit 0
            ;;
    esac
done
shift $( expr $OPTIND - 1 )

if $(test $# -lt 1); then
    _help $0
    exit
fi

RULE=$1
shift

if $( test -e "$BUILDDIR" ); then
    if $( test ! -d "$BUILDDIR" ); then
        error "$BUILDDIR is not a directory"
    fi
    debug "$BUILDDIR already exists"
else
    info "making build directory: $BUILDDIR"
    mkdir "$BUILDDIR"
fi

. $file
. $BUILDDIR/$RULE
