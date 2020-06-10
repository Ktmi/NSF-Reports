
OUTDIR="out"
DOCDIR="doc"
RESOURCEDIR="resources"

if [ ! -d "$OUTDIR" ]; then
    mkdir "$OUTDIR"
fi

PS3="Select a file to build."

BASECMD="pandoc '$RESOURCEDIR/metadata.yml' -d '$RESOURCEDIR/settings.yml'"

select filename in $DOCDIR/*.md
do
    name=$(basename $filename .md)
    eval $BASECMD $filename -o "$OUTDIR/$name.pdf"
    echo "Compiled $filename to $OUTDIR/$name.pdf"
done