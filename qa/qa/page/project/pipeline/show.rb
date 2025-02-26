# frozen_string_literal: true

module QA
  module Page
    module Project
      module Pipeline
        class Show < QA::Page::Base
          include Component::CiIcon

          view 'app/assets/javascripts/ci/pipeline_details/header/pipeline_details_header.vue' do
            element 'pipeline-details-header', required: true
          end

          view 'app/assets/javascripts/ci/pipeline_details/graph/components/job_item.vue' do
            element 'job-with-link', required: true
          end

          view 'app/assets/javascripts/ci/common/private/job_action_component.vue' do
            element 'ci-action-button'
          end

          view 'app/assets/javascripts/ci/pipeline_details/graph/components/linked_pipeline.vue' do
            element 'expand-pipeline-button'
            element 'linked-pipeline-container'
            element 'downstream-title-content'
          end

          view 'app/assets/javascripts/ci/pipeline_details/graph/components/job_group_dropdown.vue' do
            element 'job-dropdown-container'
            element 'jobs-dropdown-menu'
          end

          view 'app/assets/javascripts/ci/pipeline_details/graph/components/stage_column_component.vue' do
            element 'job-item-container', required: true
          end

          def running?(wait: 0)
            within_element('pipeline-details-header') do
              page.has_content?('running', wait: wait)
            end
          end

          def has_build?(name, status: :success, wait: nil)
            if status
              within_element('job-item-container', text: name) do
                has_selector?(".ci-status-icon-#{status}", **{ wait: wait }.compact)
              end
            else
              has_element?('job-item-container', text: name)
            end
          end

          def has_job?(job_name)
            has_element?('job-with-link', text: job_name)
          end

          def has_no_job?(job_name)
            has_no_element?('job-with-link', text: job_name)
          end

          def linked_pipelines
            all_elements('linked-pipeline-container', minimum: 1)
          end

          def find_linked_pipeline_by_title(title)
            linked_pipelines.find do |pipeline|
              within(pipeline) do
                find_element('downstream-title-content').text.include?(title)
              end
            end
          end

          def has_linked_pipeline?(title: nil)
            # If the pipeline page has loaded linked pipelines should appear, but it can take a little while,
            # especially on busier environments.
            retry_until(reload: true, message: 'Waiting for linked pipeline to appear') do
              title ? find_linked_pipeline_by_title(title) : has_element?('linked-pipeline-container')
            end
          end

          alias_method :has_child_pipeline?, :has_linked_pipeline?

          def has_no_linked_pipeline?
            has_no_element?('linked-pipeline-container')
          end

          alias_method :has_no_child_pipeline?, :has_no_linked_pipeline?

          def expand_linked_pipeline(title: nil)
            linked_pipeline = title ? find_linked_pipeline_by_title(title) : linked_pipelines.first

            within_element_by_index('linked-pipeline-container', linked_pipelines.index(linked_pipeline)) do
              click_element('expand-pipeline-button')
            end
          end

          alias_method :expand_child_pipeline, :expand_linked_pipeline

          def click_on_first_job
            first('.js-pipeline-graph-job-link', wait: QA::Support::Repeater::DEFAULT_MAX_WAIT_TIME).click
          end

          def click_job(job_name)
            # Retry due to transient bug https://gitlab.com/gitlab-org/gitlab/-/issues/347126
            QA::Support::Retrier.retry_on_exception do
              click_element('job-with-link', Project::Job::Show, text: job_name)
            end
          end

          def click_job_action(job_name)
            wait_for_requests

            within_element('job-item-container', text: job_name) do
              click_element('ci-action-button')
            end
          end

          def click_job_dropdown(job_dropdown_name)
            click_element('job-dropdown-container', text: job_dropdown_name)
          end

          def has_skipped_job_in_group?
            within_element('jobs-dropdown-menu') do
              all_elements('job-with-link', minimum: 1).all? do
                has_selector?('.ci-status-icon-skipped')
              end
            end
          end

          def has_no_skipped_job_in_group?
            within_element('jobs-dropdown-menu') do
              all_elements('job-with-link', minimum: 1).all? do
                has_no_selector?('.ci-status-icon-skipped')
              end
            end
          end
        end
      end
    end
  end
end

QA::Page::Project::Pipeline::Show.prepend_mod_with('Page::Project::Pipeline::Show', namespace: QA)
