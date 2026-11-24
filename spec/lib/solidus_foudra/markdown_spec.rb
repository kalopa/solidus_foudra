# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusFoudra::Markdown do
  it "renders paragraphs, headings, lists and inline marks" do
    md = "# Bow node\n\nA **strong** mount, *PETG*, see [docs](https://example.com/x).\n\n- one\n- two\n\n1. first\n2. `second`"
    expect(described_class.render(md)).to eq(
      "<h1>Bow node</h1>\n" \
      '<p>A <strong>strong</strong> mount, <em>PETG</em>, see <a href="https://example.com/x">docs</a>.</p>' \
      "\n<ul><li>one</li><li>two</li></ul>\n<ol><li>first</li><li><code>second</code></li></ol>"
    )
  end

  it "escapes HTML, so a description cannot inject markup" do
    expect(described_class.render("<script>alert(1)</script> & [x](javascript:alert(1))"))
      .to eq("<p>&lt;script&gt;alert(1)&lt;/script&gt; &amp; [x](javascript:alert(1))</p>")
  end

  it "is empty for nothing" do
    expect(described_class.render(nil)).to eq("")
  end

  it "uses the configured renderer when there is one" do
    SolidusFoudra.config.markdown_renderer = ->(text) { "<div>#{text}</div>" }
    expect(described_class.render("x")).to eq("<div>x</div>")
  end
end
