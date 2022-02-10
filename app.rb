require 'csv'
require 'time'
require 'nokogiri'
require 'andand'

APPLESCRIPT = <<EOF
tell application "Safari"
  do JavaScript "document.documentElement.outerHTML" in document 1
end tell
EOF

OUTFILE = ARGV[0]

FIELDS = [
  "Date",
  "Summary",
  "Rating",
  "Current Employee?",
  "Tenure",
  "Title",
  "Location",
  "Pros",
  "Cons"
]

unless OUTFILE.to_s == '' || File.exists?(OUTFILE)
  File.open(OUTFILE, 'w') do |f|
    f.write FIELDS.to_csv
  end
end

STDERR.puts "Pulling HTML..."

outer_html = `osascript -e '#{APPLESCRIPT}'`

STDERR.puts "Extracting..."

doc = Nokogiri::HTML.fragment(outer_html)

doc.css('.empReview').each do |review|  
  row = []

  next if review.at_css('.featuredFlag')

  # Parse date and title
  date_and_title = review.at_css('.authorJobTitle').andand.text
  date = date_and_title.split(" - ").first
  title = date_and_title.include?(" - ") ? date_and_title.split(" - ").last : "Anonymous Employee"

  # Date
  row << Time.parse(date).strftime('%Y-%m-%dT%H:%M:%S.%L%z')

  # Summary
  row << review.at_css('.reviewLink').text.andand.strip

  # Rating
  row << review.at_css('.ratingNumber').text.andand.to_i

  current_past = review.at_css('span:contains("Current Employee")').andand.text.andand.strip
  current_past ||= review.at_css('span:contains("Former Employee")').andand.text.andand.strip

  # Current or past employee
  if current_past
    row << current_past.andand.include?("Current") ? "Current Employee" : "Former Employee"
  else
    # Glassdoor doesn’t force employees to specify current/past
    row << "Unspecified"
  end

  # Tenure
  if current_past.include?(", ")
    row << current_past.split(", ").last.capitalize
  else
    # Not all reviews provide this
    row << "Unspecified"
  end

  # Employee Title
  row << title

  # Location
  row << review.at_css('.authorLocation').andand.text.andand.strip

  # Pros/Cons
  review.css('.v2__EIReviewDetailsV2__fullWidth')[0..1].each do |review_detail|
    review_text = review_detail.andand.css('p').andand.map(&:text).andand.join("\n")
    review_text_cleaned = review_text.
      andand.sub(/^(Pros|Cons)/, '').
      # remove numbers from ordered lists
      andand.gsub(/^[0-9]{1,2}\.\s?/, "").
      # remove dashes from unordered lists
      andand.gsub(/^\s?(\-|\•|\*)\s?/, "").
      andand.gsub(/\n/, "\n\n").
      andand.strip
    row << review_text_cleaned
  end

  unless OUTFILE.to_s == ''
    File.open(OUTFILE, 'a') do |f|
      f.write(row.to_csv)
    end
  else
    STDOUT.puts(row.to_csv)
  end
end