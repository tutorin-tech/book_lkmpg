function Span(el)
  if el.classes:includes('verb') then
    local content = pandoc.utils.stringify(el.content)
    return pandoc.RawInline('html', '<code>' .. content .. '</code>')
  end
  return el
end

return {
  { Span = Span }
}
