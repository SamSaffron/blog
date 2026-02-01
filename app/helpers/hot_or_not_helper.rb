# frozen_string_literal: true

module HotOrNotHelper
  # Highlights diff content with CSS classes for syntax coloring.
  # Uses content_tag to safely construct HTML - content is auto-escaped.
  # Each span has display:block in CSS so newlines are preserved visually.
  def highlight_diff(content)
    return "".html_safe if content.blank?

    lines = content.lines.map do |line|
      css_class = diff_line_class(line)
      content_tag(:span, line.chomp, class: css_class)
    end

    safe_join(lines)
  end

  private

  def diff_line_class(line)
    case line
    when /^@@.*@@/
      "diff-hunk"
    when /^diff --git/
      "diff-header"
    when /^index /
      "diff-index"
    when /^---/, /^\+\+\+/
      "diff-file"
    when /^\+/
      "diff-add"
    when /^-/
      "diff-del"
    else
      "diff-context"
    end
  end
end
