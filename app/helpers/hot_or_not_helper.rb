# frozen_string_literal: true

module HotOrNotHelper
  # Returns the display name for a patch's committer
  def committer_display_name(patch)
    patch.committer&.username || patch.committer_github_username.presence ||
      patch.committer_name.presence
  end

  # Returns the URL-safe slug for linking to a committer's page
  def committer_slug(patch)
    slug =
      patch.committer_github_username.presence || patch.committer_name.presence ||
        patch.committer&.username
    slug.present? ? ERB::Util.url_encode(slug) : nil
  end

  # Returns true if the patch has committer info to display
  def has_committer?(patch)
    patch.committer_github_username.present? || patch.committer_name.present? ||
      patch.committer.present?
  end

  # Renders a committer link for a patch
  def committer_link(patch, css_class: "committer-link", truncate_to: nil)
    return nil unless has_committer?(patch)

    display = committer_display_name(patch)
    display = display.truncate(truncate_to) if truncate_to
    slug = committer_slug(patch)

    link_to(display, "/hot-or-not/by/#{slug}", class: css_class)
  end

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
