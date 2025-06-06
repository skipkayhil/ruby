# coding: US-ASCII
# frozen_string_literal: false
require 'test/unit'
require 'stringio'
require_relative '../lib/parser_support'

class TestParse < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_error_line
    assert_syntax_error('------,,', /\n\z/, 'Message to pipe should end with a newline')
    assert_syntax_error("{hello\n  world}", /hello/)
  end

  def test_else_without_rescue
    assert_syntax_error(<<-END, %r"(:#{__LINE__+2}:|#{__LINE__+2} \|.+?\n.+?\^~.+?;) else without rescue"o, [__FILE__, __LINE__+1])
      begin
      else
        42
      end
    END
  end

  def test_alias_backref
    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /can't make alias/) do
      begin;
        alias $foo $1
      end;
    end
  end

  def test_command_call
    t = Object.new
    def t.foo(x); x; end

    a = false
    b = c = d = true
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a &&= t.foo 42
        b &&= t.foo 42
        c &&= t.foo nil
        d &&= t.foo false
      END
    end
    assert_equal([false, 42, nil, false], [a, b, c, d])

    a = 3
    assert_nothing_raised { eval("a &= t.foo 5") }
    assert_equal(1, a)

    a = [nil, nil, true, true]
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a[0] ||= t.foo 42
        a[1] &&= t.foo 42
        a[2] ||= t.foo 42
        a[3] &&= t.foo 42
      END
    end
    assert_equal([42, nil, true, 42], a)

    o = Object.new
    class << o
      attr_accessor :foo, :bar, :Foo, :Bar, :baz, :qux
    end
    o.foo = o.Foo = o::baz = nil
    o.bar = o.Bar = o::qux = 1
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        o.foo ||= t.foo 42
        o.bar &&= t.foo 42
        o.Foo ||= t.foo 42
        o.Bar &&= t.foo 42
        o::baz ||= t.foo 42
        o::qux &&= t.foo 42
      END
    end
    assert_equal([42, 42], [o.foo, o.bar])
    assert_equal([42, 42], [o.Foo, o.Bar])
    assert_equal([42, 42], [o::baz, o::qux])

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /Can't set variable/) do
      begin;
        $1 ||= t.foo 42
      end;
    end

    def t.bar(x); x + yield; end

    a = b = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = t.bar "foo" do
          "bar"
        end.gsub "ob", "OB"
        b = t.bar "foo" do
          "bar"
        end::gsub "ob", "OB"
      END
    end
    assert_equal("foOBar", a)
    assert_equal("foOBar", b)

    a = nil
    assert_nothing_raised do
      t.instance_eval <<-END, __FILE__, __LINE__+1
        a = bar "foo" do "bar" end
      END
    end
    assert_equal("foobar", a)

    a = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = t::bar "foo" do "bar" end
      END
    end
    assert_equal("foobar", a)

    def t.baz(*r)
      @baz = r + (block_given? ? [yield] : [])
    end

    assert_nothing_raised do
      t.instance_eval "baz (1), 2"
    end
    assert_equal([1, 2], t.instance_eval { @baz })
  end

  def test_mlhs_node
    c = Class.new
    class << c
      attr_accessor :foo, :bar, :Foo, :Bar
      FOO = BAR = nil
    end

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        c::foo, c::bar = 1, 2
        c.Foo, c.Bar = 1, 2
        c::FOO, c::BAR = 1, 2
      END
    end
    assert_equal([1, 2], [c::foo, c::bar])
    assert_equal([1, 2], [c.Foo, c.Bar])
    assert_equal([1, 2], [c::FOO, c::BAR])
  end

  def test_dynamic_constant_assignment
    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /dynamic constant/) do
      begin;
        def foo
          self::FOO, self::BAR = 1, 2
          ::FOO, ::BAR = 1, 2
        end
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /Can't set variable/) do
      begin;
        $1, $2 = 1, 2
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /dynamic constant/) do
      begin;
        def foo
          ::FOO = 1
        end
      end;
    end

    c = Class.new
    c.freeze
    assert_valid_syntax("#{<<~"begin;"}\n#{<<~'end;'}") do
      begin;
        c::FOO &= 1
        ::FOO &= 1
      end;
    end

    c = Class.new
    c.freeze
    assert_valid_syntax("#{<<~"begin;"}\n#{<<~'end;'}") do
      begin;
        c::FOO &= p 1
        ::FOO &= p 1
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /Can't set variable/) do
      begin;
        $1 &= 1
      end;
    end
  end

  def test_class_module
    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /must be CONSTANT/) do
      begin;
        class foo; end
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /in method body/) do
      begin;
        def foo
          class Foo; end
          module Bar; end
        end
      end;
    end

    assert_valid_syntax("#{<<~"begin;"}\n#{<<~'end;'}") do
      begin;
        class Foo 1; end
      end;
    end
  end

  def test_op_name
    o = Object.new
    def o.>(x); x; end
    def o./(x); x; end

    assert_nothing_raised do
      o.instance_eval <<-END, __FILE__, __LINE__+1
        undef >, /
      END
    end
  end

  def test_arg
    o = Object.new
    class << o
      attr_accessor :foo, :bar, :Foo, :Bar, :baz, :qux
    end
    o.foo = o.Foo = o::baz = nil
    o.bar = o.Bar = o::qux = 1
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        o.foo ||= 42
        o.bar &&= 42
        o.Foo ||= 42
        o.Bar &&= 42
        o::baz ||= 42
        o::qux &&= 42
      END
    end
    assert_equal([42, 42], [o.foo, o.bar])
    assert_equal([42, 42], [o.Foo, o.Bar])
    assert_equal([42, 42], [o::baz, o::qux])

    a = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = -2.0 ** 2
      END
    end
    assert_equal(-4.0, a)
  end

  def test_block_variable
    o = Object.new
    def o.foo(*r); yield(*r); end

    a = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        o.foo 1 do|; a| a = 42 end
      END
    end
    assert_nil(a)
  end

  def test_bad_arg
    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /cannot be a constant/) do
      begin;
        def foo(FOO); end
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /cannot be an instance variable/) do
      begin;
        def foo(@foo); end
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /cannot be a global variable/) do
      begin;
        def foo($foo); end
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /cannot be a class variable/) do
      begin;
        def foo(@@foo); end
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /cannot be an instance variable/) do
      begin;
        o.foo {|; @a| @a = 42 }
      end;
    end
  end

  def test_do_lambda
    a = b = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = -> do
          b = 42
        end
      END
    end
    a.call
    assert_equal(42, b)
  end

  def test_block_call_colon2
    o = Object.new
    def o.foo(x); x + yield; end

    a = b = nil
    assert_nothing_raised do
      o.instance_eval <<-END, __FILE__, __LINE__+1
        a = foo 1 do 42 end.to_s
        b = foo 1 do 42 end::to_s
      END
    end
    assert_equal("43", a)
    assert_equal("43", b)
  end

  def test_call_method
    a = b = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = proc {|x| x + "bar" }.("foo")
        b = proc {|x| x + "bar" }::("foo")
      END
    end
    assert_equal("foobar", a)
    assert_equal("foobar", b)
  end

  def test_xstring
    assert_raise(Errno::ENOENT) do
      eval("``")
    end
  end

  def test_words
    assert_equal([], %W( ))
    assert_syntax_error('%w[abc', /unterminated list/)
  end

  def test_dstr
    @@foo = 1
    assert_equal("foo 1 bar", "foo #@@foo bar")
    "1" =~ /(.)/
    assert_equal("foo 1 bar", "foo #$1 bar")
    assert_equal('foo #@1 bar', eval('"foo #@1 bar"'))
  end

  def test_dstr_disallowed_variable
    bug8375 = '[ruby-core:54885] [Bug #8375]'
    %w[@ @. @@ @@1 @@. $ $%].each do |src|
      src = '#'+src+' '
      str = assert_nothing_raised(SyntaxError, "#{bug8375} #{src.dump}") do
        break eval('"'+src+'"')
      end
      assert_equal(src, str, bug8375)
    end
  end

  def test_dsym
    assert_nothing_raised { eval(':""') }
  end

  def assert_disallowed_variable(type, noname, invalid)
    noname.each do |name|
      assert_syntax_error("proc{a = #{name} }", "'#{noname[0]}' without identifiers is not allowed as #{type} variable name")
    end
    invalid.each do |name|
      assert_syntax_error("proc {a = #{name} }", "'#{name}' is not allowed as #{type} variable name")
    end
  end

  def test_disallowed_instance_variable
    assert_disallowed_variable("an instance", %w[@ @.], %w[])
  end

  def test_disallowed_class_variable
    assert_disallowed_variable("a class", %w[@@ @@.], %w[@@1])
  end

  def test_disallowed_gloal_variable
    assert_disallowed_variable("a global", %w[$], %w[$%])
  end

  def test_arg2
    o = Object.new
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        def o.foo(a=42,*r,z,&b); b.call(r.inject(a*1000+z*100, :+)); end
      END
    end
    assert_equal(-1405, o.foo(1,2,3,4) {|x| -x })
    assert_equal(-1302, o.foo(1,2,3) {|x| -x })
    assert_equal(-1200, o.foo(1,2) {|x| -x })
    assert_equal(-42100, o.foo(1) {|x| -x })
    assert_raise(ArgumentError) { o.foo() }

    o = Object.new
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        def o.foo(a=42,z,&b); b.call(a*1000+z*100); end
      END
    end
    assert_equal(-1200, o.foo(1,2) {|x| -x } )
    assert_equal(-42100, o.foo(1) {|x| -x } )
    assert_raise(ArgumentError) { o.foo() }

    o = Object.new
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        def o.foo(*r,z,&b); b.call(r.inject(z*100, :+)); end
      END
    end
    assert_equal(-303, o.foo(1,2,3) {|x| -x } )
    assert_equal(-201, o.foo(1,2) {|x| -x } )
    assert_equal(-100, o.foo(1) {|x| -x } )
    assert_raise(ArgumentError) { o.foo() }
  end

  def test_duplicate_argument
    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", '') do
      begin;
        1.times {|&b?| }
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /duplicated argument/) do
      begin;
        1.times {|a, a|}
      end;
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /duplicated argument/) do
      begin;
        def foo(a, a); end
      end;
    end
  end

  def test_define_singleton_error
    msg = /singleton method for literals/
    assert_parse_error(%q[def ("foo").foo; end], msg)
    assert_parse_error(%q[def (1).foo; end], msg)
    assert_parse_error(%q[def ((1;1)).foo; end], msg)
    assert_parse_error(%q[def ((;1)).foo; end], msg)
    assert_parse_error(%q[def ((1+1;1)).foo; end], msg)
    assert_parse_error(%q[def ((%s();1)).foo; end], msg)
    assert_parse_error(%q[def ((%w();1)).foo; end], msg)
    assert_parse_error(%q[def ("#{42}").foo; end], msg)
    assert_parse_error(%q[def (:"#{42}").foo; end], msg)
    assert_parse_error(%q[def ([]).foo; end], msg)
    assert_parse_error(%q[def ([1]).foo; end], msg)
    assert_parse_error(%q[def (__FILE__).foo; end], msg)
    assert_parse_error(%q[def (__LINE__).foo; end], msg)
    assert_parse_error(%q[def (__ENCODING__).foo; end], msg)
    assert_parse_error(%q[def __FILE__.foo; end], msg)
    assert_parse_error(%q[def __LINE__.foo; end], msg)
    assert_parse_error(%q[def __ENCODING__.foo; end], msg)
  end

  def test_flip_flop
    all_assertions_foreach(nil,
      ['(cond1..cond2)', true],
      ['((cond1..cond2))', true],

      # '(;;;cond1..cond2)', # don't care

      '(1; cond1..cond2)',
      '(%s(); cond1..cond2)',
      '(%w(); cond1..cond2)',
      '(1; (2; (3; 4; cond1..cond2)))',
      '(1+1; cond1..cond2)',
    ) do |code, pass|
      code = code.sub("cond1", "n==4").sub("cond2", "n==5")
      if pass
        assert_equal([4,5], eval("(1..9).select {|n| true if #{code}}"))
      else
        assert_raise_with_message(ArgumentError, /bad value for range/, code) {
          verbose_bak, $VERBOSE = $VERBOSE, nil # disable "warning: possibly useless use of a literal in void context"
          begin
            eval("[4].each {|n| true if #{code}}")
          ensure
            $VERBOSE = verbose_bak
          end
        }
      end
    end
  end

  def test_op_asgn1_with_block
    t = Object.new
    a = []
    blk = proc {|x| a << x }

    # Prevent an "assigned but unused variable" warning
    _ = blk

    def t.[](_)
      yield(:aref)
      nil
    end
    def t.[]=(_, _)
      yield(:aset)
    end
    def t.dummy(_)
    end

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /block arg given in index assignment/)
    begin;
      t[42, &blk] ||= 42
    end;

    assert_syntax_error("#{<<~"begin;"}\n#{<<~'end;'}", /block arg given in index assignment/)
    begin;
      t[42, &blk] ||= t.dummy 42 # command_asgn test
    end;
  end

  def test_backquote
    t = Object.new

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        def t.`(x); "foo" + x + "bar"; end
      END
    end
    a = b = c = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        a = t.` "zzz"
        1.times {|;z| t.` ("zzz") }
      END
      t.instance_eval <<-END, __FILE__, __LINE__+1
        b = `zzz`
        c = %x(ccc)
      END
    end
    assert_equal("foozzzbar", a)
    assert_equal("foozzzbar", b)
    assert_equal("foocccbar", c)
  end

  def test_carrige_return
    assert_equal(2, eval("1 +\r\n1"))
  end

  def test_string
    mesg = 'from the backslash through the invalid char'

    e = assert_syntax_error('"\xg1"', /hex escape/)
    assert_match(/(^|\| ) \^~(?!~)/, e.message.lines.last, mesg)

    e = assert_syntax_error('"\u{1234"', 'unterminated Unicode escape')
    assert_match(/(^|\| )        \^(?!~)/, e.message.lines.last, mesg)

    e = assert_syntax_error('"\u{xxxx}"', 'invalid Unicode escape')
    assert_match(/(^|\| )    \^(?!~)/, e.message.lines.last, mesg)

    e = assert_syntax_error('"\u{xxxx', 'Unicode escape')
    if e.message.lines.first == "#{__FILE__}:#{__LINE__ - 1}: syntax errors found\n"
      assert_pattern_list([
                            /\s+\| \^ unterminated string;.+\n/,
                            /\s+\|     \^ unterminated Unicode escape\n/,
                            /\s+\|     \^ invalid Unicode escape sequence\n/,
                          ], e.message.lines[2..-1].join)
    else
      assert_pattern_list([
                            /.*: invalid Unicode escape\n.*\n/,
                            /    \^/,
                            /\n/,
                            /.*: unterminated Unicode escape\n.*\n/,
                            /    \^/,
                            /\n/,
                            /.*: unterminated string.*\n.*\n/,
                            /        \^\n/,
                          ], e.message)
    end

    e = assert_syntax_error('"\M1"', /escape character syntax/)
    assert_match(/(^|\| ) \^~~(?!~)/, e.message.lines.last, mesg)

    e = assert_syntax_error('"\C1"', /escape character syntax/)
    assert_match(/(^|\| ) \^~~(?!~)/, e.message.lines.last, mesg)

    src = '"\xD0\u{90'"\n""000000000000000000000000"
    assert_syntax_error(src, /(:#{__LINE__}:|> #{__LINE__} \|.+) unterminated/om)

    assert_syntax_error('"\u{100000000}"', /invalid Unicode escape/)
    assert_equal("", eval('"\u{}"'))
    assert_equal("", eval('"\u{ }"'))

    assert_equal("\x81", eval('"\C-\M-a"'))
    assert_equal("\177", eval('"\c?"'))

    assert_warning(/use \\C-\\s/) {assert_equal("\x00", eval('"\C- "'))}
    assert_warning(/use \\M-\\s/) {assert_equal("\xa0", eval('"\M- "'))}
    assert_warning(/use \\M-\\C-\\s/) {assert_equal("\x80", eval('"\M-\C- "'))}
    assert_warning(/use \\C-\\M-\\s/) {assert_equal("\x80", eval('"\C-\M- "'))}
    assert_warning(/use \\t/) {assert_equal("\x09", eval("\"\\C-\t\""))}
    assert_warning(/use \\M-\\t/) {assert_equal("\x89", eval("\"\\M-\t\""))}
    assert_warning(/use \\M-\\t/) {assert_equal("\x89", eval("\"\\M-\\C-\t\""))}
    assert_warning(/use \\M-\\t/) {assert_equal("\x89", eval("\"\\C-\\M-\t\""))}
    assert_syntax_error("\"\\C-\x01\"", 'Invalid escape character syntax')
    assert_syntax_error("\"\\M-\x01\"", 'Invalid escape character syntax')
    assert_syntax_error("\"\\M-\\C-\x01\"", 'Invalid escape character syntax')
    assert_syntax_error("\"\\C-\\M-\x01\"", 'Invalid escape character syntax')

    e = assert_syntax_error('"\c\u0000"', 'Invalid escape character syntax')
    assert_match(/(^|\| ) \^~~~(?!~)/, e.message.lines.last)
    e = assert_syntax_error('"\c\U0000"', 'Invalid escape character syntax')
    assert_match(/(^|\| ) \^~~~(?!~)/, e.message.lines.last)

    e = assert_syntax_error('"\C-\u0000"', 'Invalid escape character syntax')
    assert_match(/(^|\| ) \^~~~~(?!~)/, e.message.lines.last)
    e = assert_syntax_error('"\C-\U0000"', 'Invalid escape character syntax')
    assert_match(/(^|\| ) \^~~~~(?!~)/, e.message.lines.last)

    e = assert_syntax_error('"\M-\u0000"', 'Invalid escape character syntax')
    assert_match(/(^|\| ) \^~~~~(?!~)/, e.message.lines.last)
    e = assert_syntax_error('"\M-\U0000"', 'Invalid escape character syntax')
    assert_match(/(^|\| ) \^~~~~(?!~)/, e.message.lines.last)

    e = assert_syntax_error(%["\\C-\u3042"], 'Invalid escape character syntax')
    assert_match(/(^|\|\s)\s \^(?# \\ ) ~(?# C ) ~(?# - ) ~+(?# U+3042 )($|\s)/x, e.message.lines.last)
    assert_not_include(e.message, "invalid multibyte char")
  end

  def test_question
    assert_syntax_error('?', /incomplete/)
    assert_syntax_error('? ', /unexpected/)
    assert_syntax_error("?\n", /unexpected/)
    assert_syntax_error("?\t", /unexpected/)
    assert_syntax_error("?\v", /unexpected/)
    assert_syntax_error("?\r", /unexpected/)
    assert_syntax_error("?\f", /unexpected/)
    assert_syntax_error(" ?a\x8a".force_encoding("utf-8"), /invalid multibyte/)
    assert_equal("\u{1234}", eval("?\u{1234}"))
    assert_equal("\u{1234}", eval('?\u{1234}'))
    assert_equal("\u{1234}", eval('?\u1234'))
    assert_syntax_error('?\u{41 42}', 'Multiple codepoints at single character literal')
    assert_syntax_error("?and", /unexpected '\?'/)
    assert_syntax_error("?\u1234and", /unexpected '\?'/)
    e = assert_syntax_error('"#{?\u123}"', 'invalid Unicode escape')
    assert_not_match(/end-of-input/, e.message)

    assert_warning(/use ?\\C-\\s/) {assert_equal("\x00", eval('?\C- '))}
    assert_warning(/use ?\\M-\\s/) {assert_equal("\xa0", eval('?\M- '))}
    assert_warning(/use ?\\M-\\C-\\s/) {assert_equal("\x80", eval('?\M-\C- '))}
    assert_warning(/use ?\\C-\\M-\\s/) {assert_equal("\x80", eval('?\C-\M- '))}
    assert_warning(/use ?\\t/) {assert_equal("\x09", eval("?\\C-\t"))}
    assert_warning(/use ?\\M-\\t/) {assert_equal("\x89", eval("?\\M-\t"))}
    assert_warning(/use ?\\M-\\t/) {assert_equal("\x89", eval("?\\M-\\C-\t"))}
    assert_warning(/use ?\\M-\\t/) {assert_equal("\x89", eval("?\\C-\\M-\t"))}
    assert_syntax_error("?\\C-\x01", 'Invalid escape character syntax')
    assert_syntax_error("?\\M-\x01", 'Invalid escape character syntax')
    assert_syntax_error("?\\M-\\C-\x01", 'Invalid escape character syntax')
    assert_syntax_error("?\\C-\\M-\x01", 'Invalid escape character syntax')

    assert_equal("\xff", eval("# encoding: ascii-8bit\n""?\\\xFF"))
  end

  def test_percent
    assert_equal(:foo, eval('%s(foo)'))
    assert_syntax_error('%s', /unterminated quoted string/)
    assert_syntax_error('%ss', /unknown type/)
    assert_syntax_error('%z()', /unknown type/)
    assert_syntax_error("%\u3042", /unknown type/)
    assert_syntax_error("%q\u3042", /unknown type/)
    assert_syntax_error("%", /unterminated quoted string/)
  end

  def test_symbol
    bug = '[ruby-dev:41447]'
    sym = "foo\0bar".to_sym
    assert_nothing_raised(SyntaxError, bug) do
      assert_equal(sym, eval(":'foo\0bar'"))
    end
    assert_nothing_raised(SyntaxError, bug) do
      assert_equal(sym, eval(':"foo\u0000bar"'))
    end
    assert_nothing_raised(SyntaxError, bug) do
      assert_equal(sym, eval(':"foo\u{0}bar"'))
    end
    assert_nothing_raised(SyntaxError) do
      assert_equal(:foobar, eval(':"foo\u{}bar"'))
      assert_equal(:foobar, eval(':"foo\u{ }bar"'))
    end

    assert_syntax_error(':@@', /is not allowed/)
    assert_syntax_error(':@@1', /is not allowed/)
    assert_syntax_error(':@', /is not allowed/)
    assert_syntax_error(':@1', /is not allowed/)
    assert_syntax_error(':$01234', /is not allowed/)
  end

  def test_parse_string
    assert_syntax_error("/\n", /unterminated/)
  end

  def test_here_document
    x = nil

    assert_syntax_error("<\<FOO\n", /can't find string "FOO"/)

    assert_nothing_raised(SyntaxError) do
      x = eval %q(
<<FOO
#$
FOO
      )
    end
    assert_equal "\#$\n", x

    assert_syntax_error("<\<\"\n", /unterminated here document identifier/)

    assert_syntax_error("<<``\n", /can't find string ""/)

    assert_syntax_error("<<--\n", /unexpected <</)

    assert_nothing_raised(SyntaxError) do
      x = eval %q(
<<FOO
#$
foo
FOO
      )
    end
    assert_equal "\#$\nfoo\n", x

    assert_nothing_raised do
      eval "x = <<""FOO\r\n1\r\nFOO"
    end
    assert_equal("1\n", x)

    assert_nothing_raised do
      x = eval "<<' FOO'\n""[Bug #19539]\n"" FOO\n"
    end
    assert_equal("[Bug #19539]\n", x)

    assert_nothing_raised do
      x = eval "<<-' FOO'\n""[Bug #19539]\n"" FOO\n"
    end
    assert_equal("[Bug #19539]\n", x)
  end

  def test_magic_comment
    x = nil

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
# coding: utf-8
x = __ENCODING__
      END
    end
    assert_equal(Encoding.find("UTF-8"), x)

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
# coding = utf-8
x = __ENCODING__
      END
    end
    assert_equal(Encoding.find("UTF-8"), x)

    assert_raise(ArgumentError) do
      eval <<-END, nil, __FILE__, __LINE__+1
# coding = foobarbazquxquux_dummy_enconding
x = __ENCODING__
      END
    end

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
# xxxx : coding sjis
x = __ENCODING__
      END
    end
    assert_equal(__ENCODING__, x)

    assert_raise(ArgumentError) do
      EnvUtil.with_default_external(Encoding::US_ASCII) {eval <<-END, nil, __FILE__, __LINE__+1}
# coding = external
x = __ENCODING__
      END
    end

    assert_raise(ArgumentError) do
      EnvUtil.with_default_internal(Encoding::US_ASCII) {eval <<-END, nil, __FILE__, __LINE__+1}
# coding = internal
x = __ENCODING__
      END
    end

    assert_raise(ArgumentError) do
      eval <<-END, nil, __FILE__, __LINE__+1
# coding = filesystem
x = __ENCODING__
      END
    end

    assert_raise(ArgumentError) do
      eval <<-END, nil, __FILE__, __LINE__+1
# coding = locale
x = __ENCODING__
      END
    end

    e = assert_raise(ArgumentError) do
      eval <<-END, nil, __FILE__, __LINE__+1
# coding: foo
      END
    end

    message = e.message.gsub(/\033\[.*?m/, "")
    assert_include(message, "# coding: foo\n")
    assert_include(message, "          ^")

    e = assert_raise(ArgumentError) do
      eval <<-END, nil, __FILE__, __LINE__+1
# coding = foo
      END
    end

    message = e.message.gsub(/\033\[.*?m/, "")
    assert_include(message, "# coding = foo\n")
    assert_include(message, "           ^")
  end

  def test_utf8_bom
    x = nil
    assert_nothing_raised do
      eval "\xef\xbb\xbf x = __ENCODING__"
    end
    assert_equal(Encoding.find("UTF-8"), x)
    assert_raise(NameError) { eval "\xef" }
  end

  def test_dot_in_next_line
    x = nil
    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        x = 1
        .to_s
      END
    end
    assert_equal("1", x)
  end

  def test_pow_asgn
    x = 3
    assert_nothing_raised { eval("x **= 2") }
    assert_equal(9, x)
  end

  def test_embedded_rd
    assert_valid_syntax("=begin\n""=end")
    assert_valid_syntax("=begin\n""=end\0")
    assert_valid_syntax("=begin\n""=end\C-d")
    assert_valid_syntax("=begin\n""=end\C-z")
  end

  def test_embedded_rd_error
    error = 'embedded document meets end of file'
    assert_syntax_error("=begin\n", error)
    assert_syntax_error("=begin", error)
  end

  def test_float
    assert_predicate(assert_warning(/out of range/) {eval("1e10000")}, :infinite?)
    assert_syntax_error('1_E', /trailing '_'/)
    assert_syntax_error('1E1E1', /unexpected constant/)
  end

  def test_global_variable
    assert_equal(nil, assert_warning(/not initialized/) {eval('$-x')})
    assert_equal(nil, eval('alias $preserve_last_match $&'))
    assert_equal(nil, eval('alias $& $test_parse_foobarbazqux'))
    $test_parse_foobarbazqux = nil
    assert_equal(nil, $&)
    assert_equal(nil, eval('alias $& $preserve_last_match'))
    assert_syntax_error('a = $#', /as a global variable name/)
    assert_syntax_error('a = $#', /a = \$\#\n(^|.+?\| )    \^~(?!~)/)
  end

  def test_invalid_instance_variable
    pattern = /without identifiers is not allowed as an instance variable name/
    assert_syntax_error('@%', pattern)
    assert_syntax_error('@', pattern)
  end

  def test_invalid_class_variable
    pattern = /without identifiers is not allowed as a class variable name/
    assert_syntax_error('@@%', pattern)
    assert_syntax_error('@@', pattern)
  end

  def test_invalid_char
    bug10117 = '[ruby-core:64243] [Bug #10117]'
    invalid_char = /Invalid char '\\x01'/
    x = 1
    assert_in_out_err(%W"-e \x01x", "", [], invalid_char, bug10117)
    assert_syntax_error("\x01x", invalid_char, bug10117)
    assert_equal(nil, eval("\x04x"))
    assert_equal 1, x
  end

  def test_literal_concat
    x = "baz"
    assert_equal("foobarbaz", eval('"foo" "bar#{x}"'))
    assert_equal("baz", x)
  end

  def test_unassignable
    assert_syntax_error(%q(self = 1), /Can't change the value of self/)
    assert_syntax_error(%q(nil = 1), /Can't assign to nil/)
    assert_syntax_error(%q(true = 1), /Can't assign to true/)
    assert_syntax_error(%q(false = 1), /Can't assign to false/)
    assert_syntax_error(%q(__FILE__ = 1), /Can't assign to __FILE__/)
    assert_syntax_error(%q(__LINE__ = 1), /Can't assign to __LINE__/)
    assert_syntax_error(%q(__ENCODING__ = 1), /Can't assign to __ENCODING__/)
    assert_syntax_error("def foo; FOO = 1; end", /dynamic constant assignment/)
    assert_syntax_error("x, true", /Can't assign to true/)
  end

  def test_block_dup
    assert_syntax_error("foo(&proc{}) {}", /both block arg and actual block/)
  end

  def test_set_backref
    assert_syntax_error("$& = 1", /Can't set variable/)
  end

  def test_void_expr_stmts_value
    x = 1
    useless_use = /useless use/
    assert_nil assert_warning(useless_use) {eval("x; nil")}
    assert_nil assert_warning(useless_use) {eval("1+1; nil")}
    assert_nil assert_warning('') {eval("1.+(1); nil")}
    assert_nil assert_warning(useless_use) {eval("TestParse; nil")}
    assert_nil assert_warning(useless_use) {eval("::TestParse; nil")}
    assert_nil assert_warning(useless_use) {eval("x..x; nil")}
    assert_nil assert_warning(useless_use) {eval("x...x; nil")}
    assert_nil assert_warning(useless_use) {eval("self; nil")}
    assert_nil assert_warning(useless_use) {eval("nil; nil")}
    assert_nil assert_warning(useless_use) {eval("true; nil")}
    assert_nil assert_warning(useless_use) {eval("false; nil")}
    assert_nil assert_warning(useless_use) {eval("defined?(1); nil")}
    assert_nil assert_warning(useless_use) {eval("begin; ensure; x; end")}
    assert_equal 1, x

    assert_syntax_error("1; next; 2", /Invalid next/)
  end

  def test_assign_in_conditional
    # multiple assignment
    assert_warning(/'= literal' in conditional/) do
      eval <<-END, nil, __FILE__, __LINE__+1
        (x, y = 1, 2) ? 1 : 2
      END
    end

    # instance variable assignment
    assert_warning(/'= literal' in conditional/) do
      eval <<-END, nil, __FILE__, __LINE__+1
        if @x = true
          1
        else
          2
        end
      END
    end

    # local variable assignment
    assert_warning(/'= literal' in conditional/) do
      eval <<-END, nil, __FILE__, __LINE__+1
        def m
          if x = true
            1
          else
            2
          end
        end
      END
    end

    # global variable assignment
    assert_separately([], <<-RUBY)
      assert_warning(/'= literal' in conditional/) do
        eval <<-END, nil, __FILE__, __LINE__+1
          if $x = true
            1
          else
            2
          end
        END
      end
    RUBY

    # dynamic variable assignment
    assert_warning(/'= literal' in conditional/) do
      eval <<-END, nil, __FILE__, __LINE__+1
        y = 1

        1.times do
          if y = true
            1
          else
            2
          end
        end
      END
    end

    # class variable assignment
    assert_warning(/'= literal' in conditional/) do
      eval <<-END, nil, __FILE__, __LINE__+1
        c = Class.new
        class << c
          if @@a = 1
          end
        end
      END
    end

    # constant declaration
    assert_separately([], <<-RUBY)
      assert_warning(/'= literal' in conditional/) do
        eval <<-END, nil, __FILE__, __LINE__+1
          if Const = true
            1
          else
            2
          end
        END
      end
    RUBY
  end

  def test_literal_in_conditional
    assert_warning(/string literal in condition/) do
      eval <<-END, nil, __FILE__, __LINE__+1
        "foo" ? 1 : 2
      END
    end

    assert_warning(/regex literal in condition/) do
      x = "bar"
      eval <<-END, nil, __FILE__, __LINE__+1
        /foo#{x}baz/ ? 1 : 2
      END
    end

    assert_nothing_raised do
      eval <<-END, nil, __FILE__, __LINE__+1
        (true..false) ? 1 : 2
      END
    end

    assert_warning(/string literal in flip-flop/) do
      eval <<-END, nil, __FILE__, __LINE__+1
        ("foo".."bar") ? 1 : 2
      END
    end

    assert_warning(/literal in condition/) do
      x = "bar"
      eval <<-END, nil, __FILE__, __LINE__+1
        :"foo#{"x"}baz" ? 1 : 2
      END
      assert_equal "bar", x
    end
  end

  def test_no_blockarg
    assert_syntax_error("yield(&:+)", /block argument should not be given/)
  end

  def test_method_block_location
    bug5614 = '[ruby-core:40936]'
    expected = nil
    e = assert_raise(NoMethodError) do
      1.times do
        expected = __LINE__+1
      end.print do
        #
      end
    end
    actual = e.backtrace.first[/\A#{Regexp.quote(__FILE__)}:(\d+):/o, 1].to_i
    assert_equal(expected, actual, bug5614)
  end

  def test_no_shadowing_variable_warning
    assert_no_warning(/shadowing outer local variable/) {eval("a=1; tap {|a|}")}
  end

  def test_shadowing_private_local_variable
    assert_equal 1, eval("_ = 1; [[2]].each{ |(_)| }; _")
  end

  def test_unused_variable
    o = Object.new
    assert_warning(/assigned but unused variable/) {o.instance_eval("def foo; a=1; nil; end")}
    assert_warning(/assigned but unused variable/) {o.instance_eval("def bar; a=1; a(); end")}
    a = "\u{3042}"
    assert_warning(/#{a}/) {o.instance_eval("def foo0; #{a}=1; nil; end")}
    assert_warning(/assigned but unused variable/) {o.instance_eval("def foo1; tap {a=1; a()}; end")}
    assert_warning('') {o.instance_eval("def bar1; a=a=1; nil; end")}
    assert_warning(/assigned but unused variable/) {o.instance_eval("def bar2; a, = 1, 2; end")}
    assert_warning('') {o.instance_eval("def marg1(a); nil; end")}
    assert_warning('') {o.instance_eval("def marg2((a)); nil; end")}
  end

  def test_parsing_begin_statement_inside_method_definition
    assert_equal :bug_20234, eval("def (begin;end).bug_20234; end")
    NilClass.remove_method(:bug_20234)
    assert_equal :bug_20234, eval("def (begin;rescue;end).bug_20234; end")
    NilClass.remove_method(:bug_20234)
    assert_equal :bug_20234, eval("def (begin;ensure;end).bug_20234; end")
    NilClass.remove_method(:bug_20234)
    assert_equal :bug_20234, eval("def (begin;rescue;else;end).bug_20234; end")
    NilClass.remove_method(:bug_20234)

    assert_raise(SyntaxError) { eval("def (begin;else;end).bug_20234; end") }
    assert_raise(SyntaxError) { eval("def (begin;ensure;else;end).bug_20234; end") }
  end

  def test_named_capture_conflict
    a = 1
    assert_warning('') {eval("a = 1; /(?<a>)/ =~ ''")}
    a = "\u{3042}"
    assert_warning('') {eval("#{a} = 1; /(?<#{a}>)/ =~ ''")}
  end

  def test_named_capture_in_block
    all_assertions_foreach(nil,
      '(/(?<a>.*)/)',
      '(;/(?<a>.*)/)',
      '(%s();/(?<a>.*)/)',
      '(%w();/(?<a>.*)/)',
      '(1; (2; 3; (4; /(?<a>.*)/)))',
      '(1+1; /(?<a>.*)/)',
      '/#{""}(?<a>.*)/',
    ) do |code, pass|
      token = Random.bytes(4).unpack1("H*")
      if pass
        assert_equal(token, eval("#{code} =~ #{token.dump}; a"))
      else
        verbose_bak, $VERBOSE = $VERBOSE, nil # disable "warning: possibly useless use of a literal in void context"
        begin
          assert_nil(eval("#{code} =~ #{token.dump}; defined?(a)"), code)
        ensure
          $VERBOSE = verbose_bak
        end
      end
    end
  end

  def test_rescue_in_command_assignment
    bug = '[ruby-core:75621] [Bug #12402]'
    all_assertions(bug) do |a|
      a.for("lhs = arg") do
        v = bug
        v = raise(bug) rescue "ok"
        assert_equal("ok", v)
      end
      a.for("lhs op_asgn arg") do
        v = 0
        v += raise(bug) rescue 1
        assert_equal(1, v)
      end
      a.for("lhs[] op_asgn arg") do
        v = [0]
        v[0] += raise(bug) rescue 1
        assert_equal([1], v)
      end
      a.for("lhs.m op_asgn arg") do
        k = Struct.new(:m)
        v = k.new(0)
        v.m += raise(bug) rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs::m op_asgn arg") do
        k = Struct.new(:m)
        v = k.new(0)
        v::m += raise(bug) rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs.C op_asgn arg") do
        k = Struct.new(:C)
        v = k.new(0)
        v.C += raise(bug) rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs::C op_asgn arg") do
        v = Class.new
        v::C ||= raise(bug) rescue 1
        assert_equal(1, v::C)
      end
      a.for("lhs = command") do
        v = bug
        v = raise bug rescue "ok"
        assert_equal("ok", v)
      end
      a.for("lhs op_asgn command") do
        v = 0
        v += raise bug rescue 1
        assert_equal(1, v)
      end
      a.for("lhs[] op_asgn command") do
        v = [0]
        v[0] += raise bug rescue 1
        assert_equal([1], v)
      end
      a.for("lhs.m op_asgn command") do
        k = Struct.new(:m)
        v = k.new(0)
        v.m += raise bug rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs::m op_asgn command") do
        k = Struct.new(:m)
        v = k.new(0)
        v::m += raise bug rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs.C op_asgn command") do
        k = Struct.new(:C)
        v = k.new(0)
        v.C += raise bug rescue 1
        assert_equal(k.new(1), v)
      end
      a.for("lhs::C op_asgn command") do
        v = Class.new
        v::C ||= raise bug rescue 1
        assert_equal(1, v::C)
      end
    end
  end

  def test_yyerror_at_eol
    assert_syntax_error("    0b", /\^/)
    assert_syntax_error("    0b\n", /\^/)
  end

  def test_unclosed_unicode_escape_at_eol_bug_19750
    assert_separately([], "#{<<-"begin;"}\n#{<<~'end;'}")
    begin;
      assert_syntax_error("/\\u", /too short escape sequence/)
      assert_syntax_error("/\\u{", /unterminated regexp meets end of file/)
      assert_syntax_error("/\\u{\\n", /invalid Unicode list/)
      assert_syntax_error("/a#\\u{\\n/", /invalid Unicode list/)
      re = eval("/a#\\u{\n$/x")
      assert_match(re, 'a')
      assert_not_match(re, 'a#')
      re = eval("/a#\\u\n$/x")
      assert_match(re, 'a')
      assert_not_match(re, 'a#')
    end;
  end

  def test_error_def_in_argument
    assert_separately([], "#{<<-"begin;"}\n#{<<~"end;"}")
    begin;
      assert_syntax_error("def f r:def d; def f 0end", /unexpected/)
    end;

    assert_syntax_error("def\nf(000)end", /(^|\| )  \^~~/)
    assert_syntax_error("def\nf(&0)end",  /(^|\| )   \^/)
  end

  def test_method_location_in_rescue
    bug = '[ruby-core:79388] [Bug #13181]'
    obj, line = Object.new, __LINE__+1
    def obj.location
      #
      raise
    rescue
      caller_locations(1, 1)[0]
    end

    assert_equal(line, obj.location.lineno, bug)
  end

  def test_negative_line_number
    bug = '[ruby-core:80920] [Bug #13523]'
    obj = Object.new
    obj.instance_eval("def t(e = false);raise if e; __LINE__;end", "test", -100)
    assert_equal(-100, obj.t, bug)
    assert_equal(-100, obj.method(:t).source_location[1], bug)
    e = assert_raise(RuntimeError) {obj.t(true)}
    assert_equal(-100, e.backtrace_locations.first.lineno, bug)
  end

  def test_file_in_indented_heredoc
    name = '[ruby-core:80987] [Bug #13540]' # long enough to be shared
    assert_equal(name+"\n", eval("#{<<-"begin;"}\n#{<<-'end;'}", nil, name))
    begin;
      <<~HEREDOC
        #{__FILE__}
      HEREDOC
    end;
  end

  def test_heredoc_interpolation
    var = 1

    v1 = <<~HEREDOC
      something
      #{"/#{var}"}
    HEREDOC

    v2 = <<~HEREDOC
      something
      #{_other = "/#{var}"}
    HEREDOC

    v3 = <<~HEREDOC
      something
      #{("/#{var}")}
    HEREDOC

    assert_equal "something\n/1\n", v1
    assert_equal "something\n/1\n", v2
    assert_equal "something\n/1\n", v3
    assert_equal v1, v2
    assert_equal v2, v3
    assert_equal v1, v3
  end

  def test_heredoc_unterminated_interpolation
    code = <<~'HEREDOC'
    <<A+1
    #{
    HEREDOC

    assert_syntax_error(code, /can't find string "A"/)
  end

  def test_unexpected_token_error
    assert_syntax_error('"x"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', /unexpected/)
  end

  def test_unexpected_token_after_numeric
    assert_syntax_error('0000xyz', /(^|\| )    \^~~(?!~)/)
    assert_syntax_error('1.2i1.1', /(^|\| )    \^~~(?!~)/)
    assert_syntax_error('1.2.3', /(^|\| )   \^~(?!~)/)
    assert_syntax_error('1.', /unexpected end-of-input/)
    assert_syntax_error('1e', /expecting end-of-input/)
  end

  def test_truncated_source_line
    lineno = __LINE__ + 1
    e = assert_syntax_error("'0123456789012345678901234567890123456789' abcdefghijklmnopqrstuvwxyz0123456789 123456789012345678901234567890123456789",
                            /unexpected local variable or method/)

    line = e.message.lines[1]
    line.delete_prefix!("> #{lineno} | ") if line.start_with?(">")

    assert_operator(line, :start_with?, "...")
    assert_operator(line, :end_with?, "...\n")
  end

  def test_unterminated_regexp_error
    e = assert_syntax_error("/x", /unterminated regexp meets end of file/)
    assert_not_match(/unexpected tSTRING_END/, e.message)
  end

  def test_lparenarg
    o = Struct.new(:x).new
    def o.i(x)
      self.x = x
    end
    o.instance_eval {i (-1.3).abs}
    assert_equal(1.3, o.x)
    o.i(nil)
    o.instance_eval {i = 0; i (-1.3).abs; i}
    assert_equal(1.3, o.x)
  end

  def test_serial_comparison
    assert_warning(/comparison '<' after/) do
      $VERBOSE = true
      x = 1
      eval("if false; 0 < x < 2; end")
      x
    end
  end

  def test_eof
    assert_equal(42, eval("42\0""end"))
    assert_equal(42, eval("42\C-d""end"))
    assert_equal(42, eval("42\C-z""end"))
  end

  def test_eof_in_def
    assert_syntax_error("def m\n\0""end", /unexpected/)
    assert_syntax_error("def m\n\C-d""end", /unexpected/)
    assert_syntax_error("def m\n\C-z""end", /unexpected/)
  end

  def test_unexpected_eof
    assert_syntax_error('unless', /(^|\| )      \^(?!~)/)
  end

  def test_location_of_invalid_token
    assert_syntax_error('class xxx end', /(^|\| )      \^~~(?!~)/)
  end

  def test_whitespace_warning
    assert_syntax_error("\\foo", /backslash/)
    assert_syntax_error("\\ ", /escaped space/)
    assert_syntax_error("\\\t", /escaped horizontal tab/)
    assert_syntax_error("\\\f", /escaped form feed/)
    assert_syntax_error("\\\r", /escaped carriage return/)
    assert_warn(/middle of line/) {eval(" \r ")}
    assert_syntax_error("\\\v", /escaped vertical tab/)
  end

  def test_command_def_cmdarg
    assert_valid_syntax("\n#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      m def x(); end
      1.tap do end
    end;
  end

  NONASCII_CONSTANTS = [
    *%W"\u{00de} \u{00C0}".flat_map {|c| [c, c.encode("iso-8859-15")]},
    "\u{1c4}", "\u{1f2}", "\u{1f88}", "\u{370}",
    *%W"\u{391} \u{ff21}".flat_map {|c| [c, c.encode("cp932"), c.encode("euc-jp")]},
  ]

  def assert_nonascii_const
    assert_all_assertions_foreach("NONASCII_CONSTANTS", *NONASCII_CONSTANTS) do |n|
      m = Module.new
      assert_not_operator(m, :const_defined?, n)
      assert_raise_with_message(NameError, /uninitialized/) do
        m.const_get(n)
      end
      assert_nil(eval("defined?(m::#{n})"))

      v = yield m, n

      assert_operator(m, :const_defined?, n)
      assert_equal("constant", eval("defined?(m::#{n})"))
      assert_same(v, m.const_get(n))

      m.__send__(:remove_const, n)
      assert_not_operator(m, :const_defined?, n)
      assert_nil(eval("defined?(m::#{n})"))
    end
  end

  def test_nonascii_const_set
    assert_nonascii_const do |m, n|
      m.const_set(n, 42)
    end
  end

  def test_nonascii_constant
    assert_nonascii_const do |m, n|
      m.module_eval("class #{n}; self; end")
    end
  end

  def test_cdmarg_after_command_args_and_tlbrace_arg
    assert_valid_syntax('let () { m(a) do; end }')
  end

  def test_void_value_in_rhs
    w = "void value expression"
    [
      "x = return 1", "x = return, 1", "x = 1, return", "x, y = return",
      "x = begin return ensure end",
      "x = begin ensure return end",
      "x = begin return ensure return end",
      "x = begin return; rescue; return end",
      "x = begin return; rescue; return; else return end",
    ].each do |code|
      ex = assert_syntax_error(code, w)
      assert_equal(1, ex.message.scan(w).size, ->{"same #{w.inspect} warning should be just once\n#{w.message}"})
    end
    [
      "x = begin return; rescue; end",
      "x = begin return; rescue; return; else end",
    ].each do |code|
      assert_valid_syntax(code)
    end
  end

  def eval_separately(code)
    Class.new.class_eval(code)
  end

  def assert_raise_separately(error, message, code)
    assert_raise_with_message(error, message) do
      eval_separately(code)
    end
  end

  def assert_ractor_shareable(obj)
    assert Ractor.shareable?(obj), ->{"Expected #{mu_pp(obj)} to be ractor shareable"}
  end

  def assert_not_ractor_shareable(obj)
    assert !Ractor.shareable?(obj), ->{"Expected #{mu_pp(obj)} not to be ractor shareable"}
  end

  def test_shareable_constant_value_invalid
    assert_warning(/invalid value/) do
      assert_valid_syntax("# shareable_constant_value: invalid-option", verbose: true)
    end
  end

  def test_shareable_constant_value_ignored
    assert_warning(/ignored/) do
      assert_valid_syntax("nil # shareable_constant_value: true", verbose: true)
    end
  end

  def test_shareable_constant_value_simple
    obj = [['unsharable_value']]
    a, b, c = eval_separately("#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: experimental_everything
      A = [[1]]
      # shareable_constant_value: none
      B = [[2]]
      # shareable_constant_value: literal
      C = [["shareable", "constant#{nil}"]]
      D = A

      [A, B, C]
    end;
    assert_ractor_shareable(a)
    assert_not_ractor_shareable(b)
    assert_ractor_shareable(c)
    assert_equal([1], a[0])
    assert_ractor_shareable(a[0])

    a, obj = eval_separately(<<~'end;')
      # shareable_constant_value: experimental_copy
      obj = [["unshareable"]]
      A = obj
      [A, obj]
    end;

    assert_ractor_shareable(a)
    assert_not_ractor_shareable(obj)
    assert_equal obj, a
    assert !obj.equal?(a)

    bug_20339 = '[ruby-core:117186] [Bug #20339]'
    bug_20341 = '[ruby-core:117197] [Bug #20341]'
    a, b = eval_separately(<<~'end;')
      # shareable_constant_value: literal
      foo = 1
      bar = 2
      A = { foo => bar }
      B = [foo, bar]
      [A, B]
    end;

    assert_ractor_shareable(a)
    assert_ractor_shareable(b)
    assert_equal([1], a.keys, bug_20339)
    assert_equal([2], a.values, bug_20339)
    assert_equal(1, b[0], bug_20341)
    assert_equal(2, b[1], bug_20341)
  end

  def test_shareable_constant_value_literal_const_refs
    a = eval_separately("#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: literal
      # [Bug #20668]
      SOME_CONST = {
        'Object' => Object,
        'String' => String,
        'Array' => Array,
      }
      SOME_CONST
    end;
    assert_ractor_shareable(a)
  end

  def test_shareable_constant_value_nested
    a, b = eval_separately("#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: none
      class X
        # shareable_constant_value: experimental_everything
        var = [[1]]
        A = var
      end
      B = []
      [X::A, B]
    end;
    assert_ractor_shareable(a)
    assert_not_ractor_shareable(b)
    assert_equal([1], a[0])
    assert_ractor_shareable(a[0])
  end

  def test_shareable_constant_value_hash_with_keyword_splat
    a, b = eval_separately("#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: experimental_everything
      # [Bug #20927]
      x = { x: {} }
      y = { y: {} }
      A = { **x }
      B = { x: {}, **y }
      [A, B]
    end;
    assert_ractor_shareable(a)
    assert_ractor_shareable(b)
    assert_equal({ x: {}}, a)
    assert_equal({ x: {}, y: {}}, b)
  end

  def test_shareable_constant_value_unshareable_literal
    assert_raise_separately(Ractor::IsolationError, /unshareable object to C/,
                            "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: literal
      C = ["Not " + "shareable"]
    end;

    assert_raise_separately(Ractor::IsolationError, /unshareable object to B::C/,
                            "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: literal
      B = Class.new
      B::C = ["Not " + "shareable"]
    end;

    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      assert_raise_with_message(Ractor::IsolationError, /unshareable object to ::C/) do
        # shareable_constant_value: literal
        ::C = ["Not " + "shareable"]
      end
    end;

    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      assert_raise_with_message(Ractor::IsolationError, /unshareable object to ::B::C/) do
        # shareable_constant_value: literal
        ::B = Class.new
        ::B::C = ["Not " + "shareable"]
      end
    end;

    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      assert_raise_with_message(Ractor::IsolationError, /unshareable object to ::C/) do
        # shareable_constant_value: literal
        ::C ||= ["Not " + "shareable"]
      end
    end;

    assert_raise_separately(Ractor::IsolationError, /unshareable object to B::C/,
                            "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: literal
      B = Class.new
      B::C ||= ["Not " + "shareable"]
    end;

    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      assert_raise_with_message(Ractor::IsolationError, /unshareable object to ::B::C/) do
        # shareable_constant_value: literal
        ::B = Class.new
        ::B::C ||= ["Not " + "shareable"]
      end
    end;

    assert_raise_separately(Ractor::IsolationError, /unshareable object to ...::C/,
                            "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: literal
      B = Class.new
      def self.expr; B; end
      expr::C ||= ["Not " + "shareable"]
    end;
  end

  def test_shareable_constant_value_nonliteral
    assert_raise_separately(Ractor::IsolationError, /unshareable/, "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: literal
      var = [:not_frozen]
      C = var
    end;

    assert_raise_separately(Ractor::IsolationError, /unshareable/, "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: literal
      D = begin [] end
    end;
  end

  def test_shareable_constant_value_unfrozen
    assert_raise_separately(Ractor::Error, /does not freeze object correctly/,
                            "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: experimental_everything
      o = Object.new
      def o.freeze; self; end
      C = [o]
    end;
  end

  def test_shareable_constant_value_massign
    a = eval_separately("#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      # shareable_constant_value: experimental_everything
      A, = 1
    end;
    assert_equal(1, a)
  end

  def test_if_after_class
    assert_valid_syntax('module if true; Object end::Kernel; end')
    assert_valid_syntax('module while true; break Object end::Kernel; end')
    assert_valid_syntax('class if true; Object end::Kernel; end')
    assert_valid_syntax('class while true; break Object end::Kernel; end')
  end

  def test_escaped_space
    assert_syntax_error('x = \ 42', /escaped space/)
  end

  def test_label
    expected = {:foo => 1}

    code = '{"foo": 1}'
    assert_valid_syntax(code)
    assert_equal(expected, eval(code))

    code = '{foo: 1}'
    assert_valid_syntax(code)
    assert_equal(expected, eval(code))

    class << (obj = Object.new)
      attr_reader :arg
      def set(arg)
        @arg = arg
      end
    end

    assert_valid_syntax(code = "#{<<~"do;"}\n#{<<~'end;'}")
    do;
      obj.set foo:
                1
    end;
    assert_equal(expected, eval(code))
    assert_equal(expected, obj.arg)

    assert_valid_syntax(code = "#{<<~"do;"}\n#{<<~'end;'}")
    do;
      obj.set "foo":
                  1
    end;
    assert_equal(expected, eval(code))
    assert_equal(expected, obj.arg)
  end

  def test_ungettable_gvar
    assert_syntax_error('$01234', /not allowed/)
    assert_syntax_error('"#$01234"', /not allowed/)
  end

=begin
  def test_past_scope_variable
    assert_warning(/past scope/) {catch {|tag| eval("BEGIN{throw tag}; tap {a = 1}; a")}}
  end
=end

  def assert_parse(code)
    assert_kind_of(RubyVM::AbstractSyntaxTree::Node, RubyVM::AbstractSyntaxTree.parse(code))
  end

  def assert_parse_error(code, message)
    assert_raise_with_message(SyntaxError, message) do
      $VERBOSE, verbose_bak = nil, $VERBOSE
      begin
        RubyVM::AbstractSyntaxTree.parse(code)
      ensure
        $VERBOSE = verbose_bak
      end
    end
  end
end
