# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Creating the packages protection rule', :aggregate_failures, feature_category: :package_registry do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, maintainer_projects: [project]) }

  let(:package_protection_rule_attributes) { build_stubbed(:package_protection_rule, project: project) }

  let(:kwargs) do
    {
      project_path: project.full_path,
      package_name_pattern: package_protection_rule_attributes.package_name_pattern,
      package_type: 'NPM',
      push_protected_up_to_access_level: 'MAINTAINER'
    }
  end

  let(:mutation) do
    graphql_mutation(:create_packages_protection_rule, kwargs,
      <<~QUERY
      packageProtectionRule {
        packageNamePattern
        packageType
        pushProtectedUpToAccessLevel
      }
      errors
      QUERY
    )
  end

  let(:mutation_response_package_protection_rule) do
    graphql_data_at(:createPackagesProtectionRule, :packageProtectionRule)
  end

  let(:mutation_response_errors) { graphql_data_at(:createPackagesProtectionRule, :errors) }

  subject { post_graphql_mutation(mutation, current_user: user) }

  shared_examples 'a successful response' do
    it 'returns without error' do
      subject

      expect_graphql_errors_to_be_empty
      expect(mutation_response_errors).to be_empty
    end

    it 'returns the created packages protection rule' do
      subject

      expect(mutation_response_package_protection_rule).to include(
        'packageNamePattern' => kwargs[:package_name_pattern],
        'packageType' => kwargs[:package_type],
        'pushProtectedUpToAccessLevel' => kwargs[:push_protected_up_to_access_level]
      )
    end

    it 'creates one package protection rule' do
      expect { subject }.to change { ::Packages::Protection::Rule.count }.by(1)

      expect(Packages::Protection::Rule.last).to have_attributes(
        project: project,
        package_name_pattern: kwargs[:package_name_pattern],
        package_type: kwargs[:package_type].downcase,
        push_protected_up_to_access_level: kwargs[:push_protected_up_to_access_level].downcase
      )
    end
  end

  shared_examples 'an erroneous response' do
    it 'does not create one package protection rule' do
      expect { subject }.not_to change { ::Packages::Protection::Rule.count }
    end
  end

  it_behaves_like 'a successful response'

  context 'with invalid kwargs leading to error from graphql' do
    let(:kwargs) do
      super().merge!(
        package_name_pattern: '',
        package_type: 'UNKNOWN_PACKAGE_TYPE',
        push_protected_up_to_access_level: 'UNKNOWN_ACCESS_LEVEL'
      )
    end

    it_behaves_like 'an erroneous response'

    it 'returns error about required argument' do
      subject

      expect_graphql_errors_to_include(/was provided invalid value for packageType/)
      expect_graphql_errors_to_include(/pushProtectedUpToAccessLevel/)
    end
  end

  context 'with invalid kwargs leading to error from business model' do
    let(:kwargs) { super().merge!(package_name_pattern: '') }

    it_behaves_like 'an erroneous response'

    it 'returns an error' do
      subject.tap { expect(mutation_response_errors).to include(/Package name pattern can't be blank/) }
    end
  end

  context 'with existing packages protection rule' do
    let_it_be(:existing_package_protection_rule) do
      create(:package_protection_rule, project: project, push_protected_up_to_access_level: :maintainer)
    end

    let(:kwargs) { super().merge!(package_name_pattern: existing_package_protection_rule.package_name_pattern) }

    it_behaves_like 'an erroneous response'

    it 'returns an error' do
      subject.tap { expect(mutation_response_errors).to include(/Package name pattern has already been taken/) }
    end

    context 'when field `package_name_pattern` is different than existing one' do
      let(:kwargs) do
        # The field `package_name_pattern` is unique; this is why we change the value in a minimum way
        super().merge!(package_name_pattern: "#{existing_package_protection_rule.package_name_pattern}-unique")
      end

      it_behaves_like 'a successful response'
    end

    context 'when field `push_protected_up_to_access_level` is different than existing one' do
      let(:kwargs) { super().merge!(push_protected_up_to_access_level: 'DEVELOPER') }

      it_behaves_like 'an erroneous response'

      it 'returns an error' do
        subject.tap { expect(mutation_response_errors).to include(/Package name pattern has already been taken/) }
      end
    end
  end

  context 'when user does not have permission' do
    let_it_be(:anonymous) { create(:user) }
    let_it_be(:developer) { create(:user).tap { |u| project.add_developer(u) } }
    let_it_be(:guest) { create(:user).tap { |u| project.add_guest(u) } }
    let_it_be(:reporter) { create(:user).tap { |u| project.add_reporter(u) } }

    where(:user) do
      [ref(:developer), ref(:reporter), ref(:guest), ref(:anonymous)]
    end

    with_them do
      it_behaves_like 'an erroneous response'

      it 'returns an error' do
        subject.tap { expect_graphql_errors_to_include(/you don't have permission to perform this action/) }
      end
    end
  end

  context "when feature flag ':packages_protected_packages' disabled" do
    before do
      stub_feature_flags(packages_protected_packages: false)
    end

    it_behaves_like 'an erroneous response'

    it 'returns error of disabled feature flag' do
      subject.tap { expect_graphql_errors_to_include(/'packages_protected_packages' feature flag is disabled/) }
    end
  end
end
