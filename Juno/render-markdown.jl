@require "github.com/jkroso/DOM.jl" => DOM @dom @css_str
@require "github.com/JunoLab/Atom.jl" => Atom
import Markdown

renderMD(s::AbstractString) = @dom[:p s]
renderMD(p::Markdown.Paragraph) = @dom[:p map(renderMDinline, vcat(p.content))...]
renderMD(b::Markdown.BlockQuote) = @dom[:blockquote map(renderMD, vcat(p.content))...]
renderMD(l::Markdown.LaTeX) = @dom[:latex class="latex block" block=true Atom.latex2katex(l.formula)]
renderMD(l::Markdown.Link) = @dom[:a href=l.url l.text]
renderMD(md::Markdown.HorizontalRule) = @dom[:hr]

renderMD(h::Markdown.Header{l}) where l =
  DOM.Container{Symbol(:h, l)}(DOM.Attrs(), map(renderMDinline, vcat(h.text)))

renderMD(c::Markdown.Code) =
  @dom[:pre
    [:code class=isempty(c.language) ? "julia" : c.language
           block=true
      c.code]]

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
    [@dom[:li renderMDinline(item)] for item in md.items])

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

renderMDinline(v::Vector) =
  length(v) == 1 ? renderMDinline(v[1]) : @dom[:span map(renderMDinline, v)...]
renderMDinline(md::Union{Symbol,AbstractString}) = DOM.Text(string(md))
renderMDinline(md::Markdown.Bold) = @dom[:b renderMDinline(md.text)]
renderMDinline(md::Markdown.Italic) = @dom[:em renderMDinline(md.text)]
renderMDinline(md::Markdown.Image) = @dom[:img src=md.url alt=md.alt]
renderMDinline(l::Markdown.Link) = @dom[:a href=l.url renderMDinline(l.text)]
renderMDinline(br::Markdown.LineBreak) = @dom[:br]

renderMDinline(f::Markdown.Footnote) =
  @dom[:a href="#footnote-$(f.id)" class="footnote" [:span "[$(f.id)]"]]

renderMDinline(code::Markdown.Code) =
  @dom[:code class=isempty(code.language) ? "julia" : code.language
             block=false
    code.code]

renderMDinline(md::Markdown.LaTeX) =
  @dom[:latex class="latex inline" block=false Atom.latex2katex(md.formula)]
