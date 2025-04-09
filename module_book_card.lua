local capiunto = require 'capiunto'

local p = {}

function p.main(frame)
    local args = frame:getParent().args

    local headerStyle = args.headerstyle and args.headerstyle ~= ''
        and string.format('background-color:%s;', args.headerstyle)
        or 'background-color:grey;'

    local retval = capiunto.create({
        title = args.title,
        headerStyle = headerStyle,
    })
    :addImage(args.image, args.caption)
    :addRow(frame:preprocess('{{int:language}}:'), args.language)
    :addRow(frame:preprocess('{{int:authors}}:'), args.authors)
    :addHeader(frame:preprocess('{{int:additional_info}}'))
    :addRow(frame:preprocess('{{int:sections}}:'), args.sections)
    :addRow(frame:preprocess('{{int:license}}'), args.license)
    :addRow(frame:preprocess('{{int:publication_date}}:'), args.publication_date)

    return retval
end

return p
