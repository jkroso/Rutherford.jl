@use "github.com" [
  "JunoLab/Atom.jl" => Atom
  "stevengj/LaTeXStrings.jl" LaTeXString
  "jkroso" [
    "DOM.jl" => DOM @dom @css_str ["html.jl"] ["latex.jl"]
    "Prospects.jl" flat]]
import Markdown

renderMD(v::Vector) = @dom[:div map(renderMD, v)...]
renderMD(s::AbstractString) = @dom[:p parse(MIME("text/html"), s)]
renderMD(p::Markdown.Paragraph) = @dom[:p map(renderMDinline, flat(p.content))...]
renderMD(b::Markdown.BlockQuote) = @dom[:blockquote map(renderMD, flat(b.content))...]
renderMD(l::Markdown.LaTeX) = @dom[:latex class="latex block" block=true LaTeXString(l.formula)]
renderMD(l::Markdown.Link) = @dom[:a href=l.url l.text]
renderMD(::Markdown.HorizontalRule) = @dom[:hr]

renderMD(h::Markdown.Header{l}) where l =
  DOM.Container{Symbol(:h, l)}(DOM.Attrs(), map(renderMDinline, flat(h.text)))

"highlights using Atoms own highlighter when possible"
highlight(src, language) = begin
  if haskey(ENV, "ATOM_HOME")
    grammer = isempty(language) ? "text.plain" : "source.$language"
    Atom.@rpc highlight((src=src, grammer=grammer, block=true))
  elseif isempty(language)
    "<pre>$src</pre>"
  else
    read(pipeline(IOBuffer(src), `pygmentize -f html -O "noclasses" -l $language`), String)
  end
end

renderMD(c::Markdown.Code) = begin
  html = highlight(c.code, c.language)
  dom = parse(MIME("text/html"), html)
  dom.attrs[:class] = Set([css"""
                           display: flex
                           flex-direction: column
                           border-radius: 5px
                           font: 1em SourceCodePro-light
                           padding: 0.6em
                           margin: 0
                           """])
  dom
end

renderMD(f::Markdown.Footnote) =
  @dom[:div class="footnote" id="footnote-$(f.id)"
    [:p class="footnote-title" f.id]
    renderMD(f.text)]

renderMD(md::Markdown.Admonition) =
  @dom[:div class="admonition $(md.category)"
    [:p class="admonition-title $(md.category == "warning" ? "icon-alert" : "icon-info")" md.title]
    renderMD(md.content)]

renderMD(md::Markdown.List) =
  DOM.Container{Markdown.isordered(md) ? :ol : :ul}(
    DOM.Attrs(:start=>md.ordered > 1 ? string(md.ordered) : ""),
    map(renderListItem, md.items))

renderListItem(v::Vector) = @dom[:li map(renderMDinline, v)...]
renderListItem(item) = @dom[:li renderMDinline(item)]
renderListItem(item::Markdown.Paragraph) = begin
  content = item.content
  first, rest = content[1], content[2:end]
  m = first isa AbstractString ? match(r"^ *\[(x| )\] (.*)", first) : nothing
  if m != nothing
    @dom[:li class="task" css"""
                          list-style: none
                          > input[type="checkbox"]
                            height: 1em
                            margin: 0 0.5em 0 -2em
                          """
      [:input type="checkbox" checked=m.captures[1] == "x"]
      [:label renderMDinline(m.captures[2])]
      map(renderMDinline, rest)...]
  else
    @dom[:li map(renderMDinline, content)...]
  end
end

renderMD(md::Markdown.Table) = begin
  align = map(md.align) do s
    s == :c && return "center"
    s == :r && return "right"
    s == :l && return "left"
  end
  @dom[:table css"""
              border-collapse: collapse
              border-spacing: 0
              empty-cells: show
              border: 1px solid #cbcbcb
              > thead
                background-color: #e0e0e0
                color: #000
                vertical-align: bottom
              > thead > tr > th, > tbody > tr > td
                font-size: inherit
                margin: 0
                overflow: visible
                padding: 0.5em 1em
                border-width: 0 0 1px 0
              > tbody > tr:last-child > td
                border-bottom-width: 0
              """
    [:thead
      [:tr (@dom[:th align=align[i] renderMDinline(column)]
            for (i, column) in enumerate(md.rows[1]))...]]
    [:tbody
      map(md.rows[2:end]) do row
        @dom[:tr (@dom[:td align=align[i] renderMDinline(column)]
                  for (i, column) in enumerate(row))...]
      end...]]
end

renderMDinline(x) = renderMD(x)
renderMDinline(v::Vector) =
  length(v) == 1 ? renderMDinline(v[1]) : @dom[:span map(renderMDinline, v)...]
renderMDinline(md::Union{Symbol,AbstractString}) = parse(MIME("text/html"), string(md))
renderMDinline(md::Markdown.Bold) = @dom[:b renderMDinline(md.text)]
renderMDinline(md::Markdown.Italic) = @dom[:em renderMDinline(md.text)]
renderMDinline(md::Markdown.Image) = @dom[:img src=md.url alt=md.alt]
renderMDinline(l::Markdown.Link) = @dom[:a href=l.url renderMDinline(l.text)]
renderMDinline(::Markdown.LineBreak) = @dom[:br]
renderMDinline(p::Markdown.Paragraph) = renderMD(p)

renderMDinline(f::Markdown.Footnote) =
  @dom[:a href="#footnote-$(f.id)" class="footnote" [:span "[$(f.id)]"]]

renderMDinline(code::Markdown.Code) =
  @dom[:code class="inline" block=false code.code]

renderMDinline(md::Markdown.LaTeX) =
  @dom[:latex class="latex inline" block=false LaTeXString(md.formula)]
