local p = {}

function p.main(frame)
    local args = frame:getParent().args

    local wikitext = string.format('[[%s|← {{int:prev_chapter}}]] | [[%s|{{int:next_chapter}} →]]',
        args.prev_chapter or 'Introduction',
        args.next_chapter or 'Introduction')

    return mw.html.create('div')
        :css('text-align', 'center')
        :wikitext(frame:preprocess(wikitext))
    end

return p
