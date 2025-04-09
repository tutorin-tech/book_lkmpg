function CodeBlock(block)
  if block.classes[1] == "fancyvrb" or block.classes[1] == "verbatim" then
      return pandoc.RawInline('html', '<syntaxhighlight lang="C" line>' .. block.text .. '</syntaxhighlight>')
  end
  return block
end
