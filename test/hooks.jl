@testset "Hooks for Core integration" begin
    @testset "whitespace parsing" begin
        @test JuliaSyntax._core_parser_hook("", "somefile", 1, 0, :statement) == Core.svec(nothing, 0)
        @test JuliaSyntax._core_parser_hook("", "somefile", 1, 0, :statement) == Core.svec(nothing, 0)

        @test JuliaSyntax._core_parser_hook("  ", "somefile", 1, 2, :statement) == Core.svec(nothing,2)
        @test JuliaSyntax._core_parser_hook(" #==# ", "somefile", 1, 6, :statement) == Core.svec(nothing,6)

        @test JuliaSyntax._core_parser_hook(" x \n", "somefile", 1, 0, :statement) == Core.svec(:x,4)
        @test JuliaSyntax._core_parser_hook(" x \n", "somefile", 1, 0, :atom)      == Core.svec(:x,2)
    end

    @testset "filename and lineno" begin
        ex = JuliaSyntax._core_parser_hook("@a", "somefile", 1, 0, :statement)[1]
        @test Meta.isexpr(ex, :macrocall)
        @test ex.args[2] == LineNumberNode(1, "somefile")

        ex = JuliaSyntax._core_parser_hook("@a", "otherfile", 2, 0, :statement)[1]
        @test ex.args[2] == LineNumberNode(2, "otherfile")

        # Errors also propagate file & lineno
        err = JuliaSyntax._core_parser_hook("[x)", "f1", 1, 0, :statement)[1].args[1]
        @test err isa JuliaSyntax.ParseError
        @test err.source.filename == "f1"
        @test err.source.first_line == 1
        err = JuliaSyntax._core_parser_hook("[x)", "f2", 2, 0, :statement)[1].args[1]
        @test err isa JuliaSyntax.ParseError
        @test err.source.filename == "f2"
        @test err.source.first_line == 2
    end

    @testset "toplevel errors" begin
        ex = JuliaSyntax._core_parser_hook("a\nb\n[x,\ny)", "somefile", 1, 0, :all)[1]
        @test ex.head == :toplevel
        @test ex.args[1:5] == [
            LineNumberNode(1, "somefile"),
            :a,
            LineNumberNode(2, "somefile"),
            :b,
            LineNumberNode(4, "somefile"),
        ]
        @test Meta.isexpr(ex.args[6], :error)
    end

    @testset "enable_in_core!" begin
        JuliaSyntax.enable_in_core!()

        @test Meta.parse("x + 1") == :(x + 1)
        @test Meta.parse("x + 1", 1) == (:(x + 1), 6)

        # Test that parsing statements incrementally works and stops after
        # whitespace / comment trivia
        @test Meta.parse("x + 1\n(y)\n", 1) == (:(x + 1), 7)
        @test Meta.parse("x + 1\n(y)\n", 7) == (:y, 11)
        @test Meta.parse(" x#==#", 1) == (:x, 7)
        @test Meta.parse(" #==# ", 1) == (nothing, 7)

        # Check that Meta.parse throws the JuliaSyntax.ParseError rather than
        # Meta.ParseError when Core integration is enabled.
        @test_throws JuliaSyntax.ParseError Meta.parse("[x)")

        JuliaSyntax.enable_in_core!(false)
    end

    @testset "Expr(:incomplete)" begin
        JuliaSyntax.enable_in_core!()
        @test Meta.isexpr(Meta.parse("[x"), :incomplete)

        for (str, tag) in [
                "\""           => :string
                "\"\$foo"      => :string
                "#="           => :comment
                "'"            => :char
                "'a"           => :char
                "`"            => :cmd
                "("            => :other
                "["            => :other
                "begin"        => :block
                "quote"        => :block
                "let"          => :block
                "let;"         => :block
                "for"          => :other
                "for x=xs"     => :block
                "function"     => :other
                "function f()" => :block
                "macro"        => :other
                "macro f()"    => :block
                "f() do"       => :other
                "f() do x"     => :block
                "module"       => :other
                "module X"     => :block
                "baremodule"   => :other
                "baremodule X" => :block
                "mutable struct"    => :other
                "mutable struct X"  => :block
                "struct"       => :other
                "struct X"     => :block
                "if"           => :other
                "if x"         => :block
                "while"        => :other
                "while x"      => :block
                "try"          => :block
                # could be `try x catch exc body end` or `try x catch ; body end`
                "try x catch"  => :block
                "using"        => :other
                "import"       => :other
                "local"        => :other
                "global"       => :other

                "1 == 2 ?"     => :other
                "1 == 2 ? 3 :" => :other
                "1,"           => :other
                "1, "          => :other
                "1,\n"         => :other
                "1, \n"        => :other

                # Syntax which may be an error but is not incomplete
                ""             => :none
                ")"            => :none
                "1))"          => :none
                "a b"          => :none
                "()x"          => :none
                "."            => :none
            ]
            @testset "$(repr(str))" begin
                @test Base.incomplete_tag(Meta.parse(str, raise=false)) == tag
            end
        end
        JuliaSyntax.enable_in_core!(false)

        # Should not throw
        @test JuliaSyntax._core_parser_hook("+=", "somefile", 1, 0, :statement)[1] isa Expr
    end
end
