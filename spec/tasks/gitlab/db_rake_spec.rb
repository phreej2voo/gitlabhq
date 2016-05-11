require 'spec_helper'
require 'rake'

describe 'gitlab:db namespace rake task' do
  before :all do
    Rake.application.rake_require 'active_record/railties/databases'
    Rake.application.rake_require 'tasks/seed_fu'
    Rake.application.rake_require 'tasks/gitlab/db'

    # empty task as env is already loaded
    Rake::Task.define_task :environment
  end

  before do
    # Stub out db tasks
    allow(Rake::Task['db:migrate']).to receive(:invoke).and_return(true)
    allow(Rake::Task['db:schema:load']).to receive(:invoke).and_return(true)
    allow(Rake::Task['db:seed_fu']).to receive(:invoke).and_return(true)
  end

  describe 'configure' do
    it 'should invoke db:migrate when schema has already been loaded' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(true)
      expect(Rake::Task['db:migrate']).to receive(:invoke)
      expect(Rake::Task['db:schema:load']).not_to receive(:invoke)
      expect(Rake::Task['db:seed_fu']).not_to receive(:invoke)
      expect { run_rake_task('gitlab:db:configure') }.not_to raise_error
    end

    it 'should invoke db:shema:load and db:seed_fu when schema is not loaded' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(false)
      expect(Rake::Task['db:schema:load']).to receive(:invoke)
      expect(Rake::Task['db:seed_fu']).to receive(:invoke)
      expect(Rake::Task['db:migrate']).not_to receive(:invoke)
      expect { run_rake_task('gitlab:db:configure') }.not_to raise_error
    end

    it 'should not invoke any other rake tasks during an error' do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(RuntimeError, 'error')
      expect(Rake::Task['db:migrate']).not_to receive(:invoke)
      expect(Rake::Task['db:schema:load']).not_to receive(:invoke)
      expect(Rake::Task['db:seed_fu']).not_to receive(:invoke)
      expect { run_rake_task('gitlab:db:configure') }.to raise_error(RuntimeError, 'error')
      # unstub connection so that the database cleaner still works
      allow(ActiveRecord::Base).to receive(:connection).and_call_original
    end

    it 'should not invoke seed after a failed schema_load' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_return(false)
      allow(Rake::Task['db:schema:load']).to receive(:invoke).and_raise(RuntimeError, 'error')
      expect(Rake::Task['db:schema:load']).to receive(:invoke)
      expect(Rake::Task['db:seed_fu']).not_to receive(:invoke)
      expect(Rake::Task['db:migrate']).not_to receive(:invoke)
      expect { run_rake_task('gitlab:db:configure') }.to raise_error(RuntimeError, 'error')
    end
  end

  def run_rake_task(task_name)
    Rake::Task[task_name].reenable
    Rake.application.invoke_task task_name
  end
end
