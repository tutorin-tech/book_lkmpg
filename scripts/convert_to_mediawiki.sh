#!/bin/bash

SECTIONS_NUM=21

HTML_FILES=($(seq -f "html/%02g.html" 1 "${SECTIONS_NUM}"))

TEX_FILES=($(seq -f "chunked_tex/%02g.tex" 1 "${SECTIONS_NUM}"))

WIKI_FILES=($(seq -f '"%02g.wiki"' -s ", " 1 "${SECTIONS_NUM}"))

echo "Start..."

# Remove the title and the TOC
sed '/\\maketitle/, /\\fi/d' lkmpg.tex > lkmpg_chunked.tex

echo "Split the TEX file by sections"

python -c 'import utils; utils.preprocess_tex_file("lkmpg_chunked.tex")'

echo "Convert the TEX files to the HTML format"

for file in "${TEX_FILES[@]}"; do
    echo "Process $file..."
    make4ht --shell-escape --utf8 --format html5 --output-dir html "$file" "fn-in" || exit 1
done

rm -rf *.{4ct,4tc,aux,dvi,html,idv,lg,log,pyg,svg,tmp,xref} {01..21}*.css _minted-* chunked_tex lkmpg_chunked.tex

echo "Convert the HTML files to the MediaWiki format"

for file in "${HTML_FILES[@]}"; do
    echo "Process $file..."
    pandoc \
        --standalone \
        --to mediawiki \
        --lua-filter=wrap_fancyvrb_in_syntaxhighlight.lua \
        --lua-filter=wrap_verb_in_code.lua \
        "$file" \
        --output "$(basename "$file" .html).wiki"
done

echo "Deploying the book..."

python -c 'import utils; utils.deploy_book('"${WIKI_FILES[*]}"')'

echo "Done!"
