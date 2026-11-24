# frozen_string_literal: true

# Copyright (c) 2026, Kalopa Robotics Limited.
# Licensed under the Apache License, Version 2.0; see LICENSE for details.

require "cgi"

module SolidusFoudra
  # Foudra's part descriptions are Markdown; Solidus shows a product's
  # description as HTML. Solidus pulls in no Markdown gem and a runtime
  # dependency for this alone isn't worth it, so this is the small subset
  # part descriptions use: paragraphs, headings, bullet and numbered lists,
  # **bold**, *italic*, `code` and [links](https://…). Everything is
  # HTML-escaped first, so nothing in a description can inject markup.
  # A shop with a Markdown gem it trusts sets config.markdown_renderer.
  module Markdown
    module_function

    def render(text)
      return "" if text.blank?

      custom = SolidusFoudra.config.markdown_renderer
      return custom.call(text.to_s) if custom

      blocks(text.to_s.gsub("\r\n", "\n")).join("\n")
    end

    def blocks(text)
      out = []
      list = nil
      paragraph = []
      flush_paragraph = lambda do
        out << "<p>#{paragraph.map { |l| inline(l) }.join("\n")}</p>" if paragraph.any?
        paragraph = []
      end
      flush_list = lambda do
        out << "<#{list[:tag]}>#{list[:items].map { |i| "<li>#{inline(i)}</li>" }.join}</#{list[:tag]}>" if list
        list = nil
      end

      text.each_line(chomp: true) do |line|
        if line.strip.empty?
          flush_paragraph.call
          flush_list.call
        elsif (m = line.match(/\A(\#{1,6})\s+(.*)\z/))
          flush_paragraph.call
          flush_list.call
          level = m[1].length
          out << "<h#{level}>#{inline(m[2].sub(/\s+#+\s*\z/, ""))}</h#{level}>"
        elsif (m = line.match(/\A\s*(?:[-*+]|(\d+)[.)])\s+(.*)\z/))
          flush_paragraph.call
          tag = m[1] ? "ol" : "ul"
          flush_list.call if list && list[:tag] != tag
          list ||= {tag:, items: []}
          list[:items] << m[2]
        elsif list && line.start_with?("  ")
          list[:items][-1] = "#{list[:items].last} #{line.strip}"
        else
          flush_list.call
          paragraph << line.strip
        end
      end
      flush_paragraph.call
      flush_list.call
      out
    end

    def inline(text)
      html = CGI.escapeHTML(text)
      codes = []
      html = html.gsub(/`([^`]+)`/) do
        codes << "<code>#{Regexp.last_match(1)}</code>"
        "\u0000#{codes.length - 1}\u0000"
      end
      html = html.gsub(/\[([^\]]+)\]\((https?:[^)\s]+)\)/) do
        %(<a href="#{Regexp.last_match(2)}">#{Regexp.last_match(1)}</a>)
      end
      html = html.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
      html = html.gsub(/(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?![*\w])/, '<em>\1</em>')
      html.gsub(/\u0000(\d+)\u0000/) { codes[Regexp.last_match(1).to_i] }
    end
  end
end
