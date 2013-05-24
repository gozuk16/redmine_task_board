class TaskboardController < ApplicationController
  unloadable

  before_filter :find_project
  before_filter :authorize
  helper_method :column_manager_locals

  def index
    @columns = TaskBoardColumn.find_all_by_project_id(@project.id, :order => 'weight')
    @status_names = Hash.new
    IssueStatus.select([:id, :name]).each do |status|
      @status_names[status.id] = status.name
    end

    # リードタイムを求める
    resolved_id = 3   #解決(3)
    accepted_id = 23  #受付(23)
    inprogress_id = 2 #進行中(2)
    new_id = 1        #新規(1)
    finished_id = 5   #完了(5)
    journals = Journal.select("journals.journalized_id, journals.created_on") \
      .joins('INNER JOIN issues ON journals.journalized_id = issues.id') \
      .joins('INNER JOIN journal_details ON journal_details.journal_id = journals.id') \
      .where("issues.project_id = ? AND issues.status_id IN (?, ?) AND journal_details.prop_key = 'status_id' AND journal_details.value = ?", \
              @project.id, resolved_id, finished_id, resolved_id)
    lead_times = Hash.new
    journals.each do |journal|
      # 受付
      accepted_date = Journal.find(:first,
        :select => :created_on,
        :joins => 'INNER JOIN journal_details ON journal_details.journal_id = journals.id',
        :conditions => ["journals.journalized_id = ? AND journal_details.prop_key = 'status_id' AND journal_details.value IN (?, ?)",
                        journal.journalized_id, accepted_id, new_id],
        :order => "created_on desc")
      if accepted_date != nil then
        lead_times[journal.journalized_id] = Time.at(journal.created_on) - Time.at(accepted_date.created_on)
        logger.debug "id:#{journal.journalized_id}, resolved:#{Time.at(journal.created_on)}, accepted:#{Time.at(accepted_date.created_on)}"
      end
    end
    # リードタイムの平均を求める
    @lead_time_days1 = ""
    @lead_time_hours1 = ""
    @lead_time_mins1 = ""
    if lead_times.size > 0 then
      lead_time = lead_times.values.inject(0.0){|r,i| r+=i }/lead_times.values.size
      @lead_time_days1 = lead_time.divmod(24*60*60)
      @lead_time_hours1 = @lead_time_days1[1].divmod(60*60)
      @lead_time_mins1 = @lead_time_hours1[1].divmod(60)
    end
    lead_times.clear
    journals.each do |journal|
      # 進行中
      inprogress_date = Journal.find(:first,
        :select => :created_on,
        :joins => 'INNER JOIN journal_details ON journal_details.journal_id = journals.id',
        :conditions => ["journals.journalized_id = ? AND journal_details.prop_key = 'status_id' AND journal_details.value IN (?, ?, ?)",
                        journal.journalized_id, inprogress_id, accepted_id, new_id],
        :order => "created_on desc")
      if inprogress_date != nil then
        lead_times[journal.journalized_id] = Time.at(journal.created_on) - Time.at(inprogress_date.created_on)
        logger.debug "id:#{journal.journalized_id}, resolved:#{Time.at(journal.created_on)}, inprogress:#{Time.at(inprogress_date.created_on)}"
      end
    end
    @lead_time_days2 = ""
    @lead_time_hours2 = ""
    @lead_time_mins2 = ""
    if lead_times.size > 0 then
      lead_time = lead_times.values.inject(0.0){|r,i| r+=i }/lead_times.values.size
      @lead_time_days2 = lead_time.divmod(24*60*60)
      @lead_time_hours2 = @lead_time_days2[1].divmod(60*60)
      @lead_time_mins2 = @lead_time_hours2[1].divmod(60)
    end

  end

  def save
    params[:sort].each do |status_id, issues|
      weight = 0;
      issues.each do |issue_id|
        tbi = TaskBoardIssue.find_by_issue_id(issue_id).update_attribute(:project_weight, weight)
        weight += 1
      end
    end
    if params[:move] then
      params[:move].each do |issue_id, new_status_id|
        issue = Issue.find(issue_id).update_attribute(:status_id, new_status_id)
      end
    end
    respond_to do |format|
      format.js{ head :ok }
    end
  end

  def archive_issues
    params[:ids].each do |issue_id|
      TaskBoardIssue.find_by_issue_id(issue_id).update_attribute(:is_archived, true)
    end
    respond_to do |format|
      format.js{ head :ok }
    end
  end

  def unarchive_issue
    TaskBoardIssue.find_by_issue_id(params[:issue_id]).update_attribute(:is_archived, false)
    respond_to do |format|
      format.js{ head :ok }
    end
  end

  def create_column
    @column = TaskBoardColumn.new :project => @project, :title => params[:title]
    @column.save
    render 'settings/update'
  end

  def delete_column
    @column = TaskBoardColumn.find(params[:column_id])
    @column.delete
    render 'settings/update'
  end
  
  def update_columns
    params[:column].each do |column_id, new_state|
      column = TaskBoardColumn.find(column_id.to_i)
      print column.title + ' ' + new_state[:weight] + ". "
      column.weight = new_state[:weight].to_i
      column.max_issues = new_state[:max_issues].to_i
      column.save!
      column.issue_statuses.clear()
    end
    params[:status].each do |status_id, column_id|
      status_id = status_id.to_i
      column_id = column_id.to_i
      unless column_id == 0
        @columns = TaskBoardColumn.find(column_id)
        #@column.issue_statuses << IssueStatus.find(status_id)
        @columns.issue_statuses << IssueStatus.find(status_id)
      end
    end
    render 'settings/update'
  end

  private

  def find_project
    # @project variable must be set before calling the authorize filter
    if (params[:project_id]) then
      @project = Project.find(params[:project_id])
    elsif(params[:issue_id]) then
      @project = Issue.find(params[:issue_id]).project
    end
  end

end
