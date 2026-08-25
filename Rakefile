require "bundler/gem_tasks"
require "fileutils"
require "rake/testtask"
require "yard"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

YARD::Rake::YardocTask.new do |task|
  task.before = -> { FileUtils.rm_rf(File.expand_path("doc", __dir__)) }
end

task :default => :test
