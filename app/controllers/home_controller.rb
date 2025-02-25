class HomeController < ApplicationController
  require 'roo'
  require 'pdf-reader'
  require 'openai'
  require 'write_xlsx'

  def generate_summaries
    excel_file = params[:excel_file]
    pdf_files = params[:pdf_files]
  
    topics = extract_topics_from_excel(excel_file)
    pdf_text = extract_text_from_pdfs(pdf_files)
  
    results = process_topics_with_openai(topics, pdf_text)
    file_path = generate_result_excel(results)
  
    redirect_to download_summaries_path(file_name: File.basename(file_path))
  end  

  def download_summaries
    file_path = Rails.root.join("tmp", params[:file_name])
  
    if File.exist?(file_path)
      send_file file_path, type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", disposition: "attachment"
    else
      render plain: "File not found", status: :not_found
    end
  end
  

  private

  def extract_topics_from_excel(file)
    xlsx = Roo::Spreadsheet.open(file.path)
    xlsx.sheet(0).column(1).compact
  end

  def extract_text_from_pdfs(files)
    files = Array(files).reject(&:blank?) # Ensure files is always an array and remove empty entries
    extracted_text = []

    files.each do |file|
      next unless file.respond_to?(:tempfile) # Skip invalid files
      
      reader = PDF::Reader.new(file.tempfile.path)
      reader.pages.each_with_index do |page, index|
        extracted_text << { page: index + 1, text: page.text }
      end
    end

    extracted_text
  end  

  def process_topics_with_openai(topics, pdf_text)
    token = ENV["openai_api_key"]
    connection = Faraday.new('https://api.openai.com')
    headers = { authorization: "Bearer #{token}", 'Content-Type': 'application/json' }

    prompt = <<~PROMPT
      You are a helpful assistant. You will receive a list of topics and a document split into multiple pages.
      Find all occurrences of each topic and provide:
      - The **page number**
      - The **paragraph number**
      - A **summary of the relevant paragraph**
      
      ### Topics:
      #{topics.join(", ")}

      ### Document:
      #{pdf_text.map { |p| "Page #{p[:page]}:\n#{p[:text]}" }.join("\n\n")}
      
      Provide results in this format:
      "Topic: <topic>, Page: <page_number>, Paragraph: <paragraph_number>, Summary: <summary>"
    PROMPT

    messages = [{ role: 'system', content: prompt }]

    response = connection.post('/v1/chat/completions') do |req|
      req.headers = headers
      req.body = { model: 'gpt-4o', messages: messages }.to_json
    end

    raw_results = JSON.parse(response.body).dig("choices", 0, "message", "content") || ""
    
    # Parse response into structured data
    results = []
    raw_results.each_line do |line|
      match = line.match(/Topic: (.+?), Page: (\d+), Paragraph: (\d+), Summary: (.+)/)
      next unless match
      
      results << { topic: match[1], page: match[2].to_i, paragraph: match[3].to_i, summary: match[4] }
    end

    results
  end

  def generate_result_excel(results)
    file_path = Rails.root.join("tmp", "results.xlsx")
    workbook = WriteXLSX.new(file_path)

    worksheet = workbook.add_worksheet("Results")
    worksheet.write(0, 0, "Topic")
    worksheet.write(0, 1, "Page Number")
    worksheet.write(0, 2, "Paragraph Number")
    worksheet.write(0, 3, "Summary")

    results.each_with_index do |row, index|
      worksheet.write(index + 1, 0, row[:topic])
      worksheet.write(index + 1, 1, row[:page])
      worksheet.write(index + 1, 2, row[:paragraph])
      worksheet.write(index + 1, 3, row[:summary])
    end

    workbook.close
    file_path
  end
end
