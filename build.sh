
OUTDIR="out"

if [ ! -d "$OUTDIR" ]; then
    mkdir "$OUTDIR"
fi

PS3="Select a file to build."

select filename in *.md
do
    name=$(basename $filename .md)
    pandoc metadata.yml $file -d settings.yml -o "$OUTDIR/$name.pdf"
    echo "Compiled $filename to $name.pdf"
done