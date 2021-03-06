type Table
    rows::Vector{Vector{Any}}
    align::Vector{Symbol}
end

function parserow(stream::IO)
    withstream(stream) do
        line = readline(stream) |> chomp
        row = split(line, "|")
        length(row) == 1 && return
        row[1] == "" && shift!(row)
        map!(strip, row)
        row[end] == "" && pop!(row)
        return row
    end
end

function rowlength!(row, len)
    while length(row) < len push!(row, "") end
    while length(row) > len pop!(row) end
    return row
end

const default_align = :r

function parsealign(row)
    align = Symbol[]
    for s in row
        (length(s) ≥ 3 && s ⊆ Set("-:")) || return
        push!(align,
              s[1] == ':' ? (s[end] == ':' ? :c : :l) :
              s[end] == ':' ? :r :
              default_align)
    end
    return align
end

function github_table(stream::IO, md::MD)
    withstream(stream) do
        skipblank(stream)
        rows = []
        cols = 0
        align = nothing
        while (row = parserow(stream)) != nothing
            if length(rows) == 0
                row[1] == "" && return false
                cols = length(row)
            end
            if align == nothing && length(rows) == 1 # Must have a --- row
                align = parsealign(row)
                (align == nothing || length(align) != cols) && return false
            else
                push!(rows, map(x -> parseinline(x, md), rowlength!(row, cols)))
            end
        end
        length(rows) <= 1 && return false
        push!(md, Table(rows, align))
        return true
    end
end

function html(io::IO, md::Table)
    withtag(io, :table) do
        for (i, row) in enumerate(md.rows)
            withtag(io, :tr) do
                for c in md.rows[i]
                    withtag(io, i == 1 ? :th : :td) do
                        htmlinline(io, c)
                    end
                end
            end
        end
    end
end

mapmap(f, xss) = map(xs->map(f, xs), xss)

colwidths(rows; len = length, min = 0) =
    max(min, convert(Vector{Vector{Int}}, mapmap(len, rows))...)

padding(width, twidth, a) =
    a == :l ? (0, twidth - width) :
    a == :r ? (twidth - width, 0) :
    a == :c ? (floor(Int, (twidth-width)/2), ceil(Int, (twidth-width)/2)) :
    error("Invalid alignment $a")

function padcells!(rows, align; len = length, min = 0)
    widths = colwidths(rows, len = len, min = min)
    for i = 1:length(rows), j = 1:length(rows[1])
        cell = rows[i][j]
        lpad, rpad = padding(len(cell), widths[j], align[j])
        rows[i][j] = " "^lpad * cell * " "^rpad
    end
    return rows
end

_dash(width, align) =
    align == :l ? ":" * "-"^(width-1) :
    align == :r ? "-"^(width-1) * ":" :
    align == :c ? ":" * "-"^(width-2) * ":" :
    throw(ArgumentError("Invalid alignment $align"))

function plain(io::IO, md::Table)
    cells = mapmap(plaininline, md.rows)
    padcells!(cells, md.align, len = length, min = 3)
    for i = 1:length(cells)
        print_joined(io, cells[i], " | ")
        println(io)
        if i == 1
            print_joined(io, [_dash(length(cells[i][j]), md.align[j]) for j = 1:length(cells[1])], " | ")
            println(io)
        end
    end
end

function term(io::IO, md::Table, columns)
    cells = mapmap(terminline, md.rows)
    padcells!(cells, md.align, len = ansi_length)
    for i = 1:length(cells)
        print_joined(io, cells[i], " ")
        println(io)
        if i == 1
            print_joined(io, ["–"^ansi_length(cells[i][j]) for j = 1:length(cells[1])], " ")
            println(io)
        end
    end
end

function latex(io::IO, md::Table)
    wrapblock(io, "tabular") do
        align = md.align
        println(io, "{$(join(align, " | "))}")
        for (i, row) in enumerate(md.rows)
            for (j, cell) in enumerate(row)
                j != 1 && print(io, " & ")
                latexinline(io, cell)
            end
            println(io, " \\\\")
            if i == 1
                println("\\hline")
            end
        end
    end
end
