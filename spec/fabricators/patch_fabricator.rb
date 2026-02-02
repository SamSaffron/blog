# frozen_string_literal: true

Fabricator(:patch) do
  commit_hash { sequence(:commit_hash) { |n| "abc#{n.to_s.rjust(37, "0")}" } }
  title { sequence(:title) { |n| "Fix issue ##{n}" } }
  active { true }
  hot_count { 0 }
  not_count { 0 }
end
