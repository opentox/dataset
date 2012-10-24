=begin
* Name: task.rb
* Description: Task shims
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end


module OpenTox

  # Shims for the Task class
  class Task

    # Check status of a task
    # @return [String] Status
    def status
      self[RDF::OT.hasStatus]
    end

  end

end
