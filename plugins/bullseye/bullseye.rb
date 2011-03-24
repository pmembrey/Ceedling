require 'plugin'
require 'constants'

BULLSEYE_ROOT_NAME         = 'bullseye'
BULLSEYE_TASK_ROOT         = BULLSEYE_ROOT_NAME + ':'
BULLSEYE_CONTEXT           = BULLSEYE_ROOT_NAME.to_sym

BULLSEYE_BUILD_PATH        = "#{PROJECT_BUILD_ROOT}/#{BULLSEYE_ROOT_NAME}"
BULLSEYE_BUILD_OUTPUT_PATH = "#{BULLSEYE_BUILD_PATH}/out"
BULLSEYE_RESULTS_PATH      = "#{BULLSEYE_BUILD_PATH}/results"
BULLSEYE_DEPENDENCIES_PATH = "#{BULLSEYE_BUILD_PATH}/dependencies"
BULLSEYE_ARTIFACTS_PATH    = "#{PROJECT_BUILD_ARTIFACTS_ROOT}/#{BULLSEYE_ROOT_NAME}"

# because of when in setup BULLSEYE_ARTIFACTS_PATH is available, we slip
# covfile into environment here instead of through [:environment] facility in config yaml
ENVIRONMENT_COVFILE = File.join( BULLSEYE_ARTIFACTS_PATH, 'test.cov' )
ENV['COVFILE']      = ENVIRONMENT_COVFILE


class Bullseye < Plugin

  attr_reader :config

  def setup
    @result_list = []  
  
    @config = {
      :project_test_build_output_path => BULLSEYE_BUILD_OUTPUT_PATH,
      :project_test_results_path      => BULLSEYE_RESULTS_PATH,
      :project_test_dependencies_path => BULLSEYE_DEPENDENCIES_PATH,
      }
    
    @coverage_template_all = @ceedling[:file_wrapper].read( File.join( PLUGINS_BULLSEYE_PATH, 'template.erb') )
  end

  def generate_coverage_object_file(source, object)
    compile_command  = @ceedling[:tool_executor].build_command_line(TOOLS_BULLSEYE_COMPILER, source, object)
    coverage_command = @ceedling[:tool_executor].build_command_line(TOOLS_BULLSEYE_INSTRUMENTATION, compile_command[:line] )
    @ceedling[:streaminator].stdout_puts("Compiling #{File.basename(source)} with coverage...")
    @ceedling[:tool_executor].exec( coverage_command[:line], coverage_command[:options] )
  end

  def post_test_execute(arg_hash)
    result_file = arg_hash[:result_file]
  
    if ((result_file =~ /#{BULLSEYE_RESULTS_PATH}/) and (not @result_list.include?(result_file)))
      @result_list << arg_hash[:result_file]
    end
  end
    
  def post_build
    return if (not @ceedling[:task_invoker].invoked?(/^#{BULLSEYE_TASK_ROOT}/))

    # test results
    results = @ceedling[:plugin_reportinator].assemble_test_results(@result_list)
    hash = {
      :header => BULLSEYE_ROOT_NAME.upcase,
      :results => results
    }
    
    @ceedling[:plugin_reportinator].run_test_results_report(hash) do
      message = ''
      message = 'Unit test failures.' if (results[:counts][:failed] > 0)
      message
    end
    
    # coverage results
    command      = @ceedling[:tool_executor].build_command_line(TOOLS_BULLSEYE_REPORT_COVSRC)
    shell_result = @ceedling[:tool_executor].exec(command[:line], command[:options])

    if (@ceedling[:task_invoker].invoked?(/^#{BULLSEYE_TASK_ROOT}(all|delta)/))
      report_coverage_results_all(shell_result[:output])
    else
      report_per_function_coverage_results(@ceedling[:test_invoker].sources)
    end
  end

  def summary
    result_list = @ceedling[:file_path_utils].form_pass_results_filelist( BULLSEYE_RESULTS_PATH, COLLECTION_ALL_TESTS )

    # test results
    # get test results for only those tests in our configuration and of those only tests with results on disk
    hash = {
      :header => BULLSEYE_ROOT_NAME.upcase,
      :results => @ceedling[:plugin_reportinator].assemble_test_results(result_list, {:boom => false})
    }

    @ceedling[:plugin_reportinator].run_test_results_report(hash)
    
    # coverage results
    command = @ceedling[:tool_executor].build_command_line(TOOLS_BULLSEYE_REPORT_COVSRC)
    shell_result = @ceedling[:tool_executor].exec(command[:line], command[:options])
    report_coverage_results_all(shell_result[:output])
  end

  private ###################################

  def report_coverage_results_all(coverage)
    results = {
      :coverage => {
        :functions => nil,
        :branches  => nil
      }
    }

    if (coverage =~ /^Total.*?=\s+([0-9]+)\%/)
      results[:coverage][:functions] = $1.to_i
    end
    
    if (coverage =~ /^Total.*=\s+([0-9]+)\%\s*$/)
      results[:coverage][:branches] = $1.to_i
    end

    @ceedling[:plugin_reportinator].run_report($stdout, @coverage_template_all, results)
  end

  def report_per_function_coverage_results(sources)
    banner = @ceedling[:plugin_reportinator].generate_banner "#{BULLSEYE_ROOT_NAME.upcase}: CODE COVERAGE SUMMARY"
    @ceedling[:streaminator].stdout_puts "\n" + banner

    sources.each do |source|
      command          = @ceedling[:tool_executor].build_command_line(TOOLS_BULLSEYE_REPORT_COVFN, source)
      shell_results    = @ceedling[:tool_executor].exec(command[:line], command[:options])
      coverage_results = shell_results[:output]
      coverage_results.sub!(/.*\n.*\n/,'') # Remove the Bullseye tool banner
      if (coverage_results =~ /warning cov814: report is empty/)
        coverage_results = "WARNING: #{source} contains no coverage data!\n\n"
        @ceedling[:streaminator].stdout_puts(coverage_results, Verbosity::COMPLAIN)
      else
        coverage_results += "\n"
        @ceedling[:streaminator].stdout_puts(coverage_results)
      end
    end
  end

end

# end blocks always executed following rake run
END {
  # cache our input configurations to use in comparison upon next execution
  @ceedling[:cacheinator].cache_test_config( @ceedling[:setupinator].config_hash ) if (@ceedling[:task_invoker].invoked?(/^#{BULLSEYE_TASK_ROOT}/))
}
