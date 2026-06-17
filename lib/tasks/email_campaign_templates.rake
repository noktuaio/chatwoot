require 'open3'

namespace :email_campaign_templates do
  SEED_DIR = Rails.root.join('db/seeds/email_templates').freeze
  MJML_COMPILER = Rails.root.join('lib/tasks/support/mjml_compile.js').freeze

  # Imports the curated Mailteorite MJML templates (MIT) from db/seeds/email_templates/<category>/*.mjml
  # into GLOBAL EmailCampaignTemplate rows (account_id = nil) so every account sees the same gallery.
  #
  # body_html is compiled at seed time via the same mjml-browser@4.18 the editor uses (so previews work
  # without a client round-trip). If Node/mjml is unavailable, body_html stays nil and the client compiles
  # body_mjml on demand. The locked unsubscribe footer is guaranteed via the AI Sanitizer (idempotent).
  #
  # Idempotent: re-running upserts by (account_id IS NULL, name).
  #
  # Usage: bundle exec rails email_campaign_templates:seed
  desc 'Seed GLOBAL email campaign gallery templates from db/seeds/email_templates'
  task seed: :environment do
    files = Dir.glob(SEED_DIR.join('**/*.mjml')).sort
    abort("No .mjml files found in #{SEED_DIR}") if files.empty?

    compiler_available = mjml_compiler_available?
    puts(compiler_available ? 'MJML compiler available — seeding body_html.' : 'MJML compiler unavailable — body_html left nil (client compiles).')

    imported = 0
    files.each do |path|
      category = File.basename(File.dirname(path))
      name = template_name(path)
      mjml = EmailCampaigns::Ai::Sanitizer.new(File.read(path)).perform
      precompiled = path.sub(/\.mjml\z/, '.html')
      html = if File.exist?(precompiled)
               File.read(precompiled)
             elsif compiler_available
               compile_mjml(mjml)
             end

      template = EmailCampaignTemplate.find_or_initialize_by(account_id: nil, name: name)
      template.assign_attributes(body_mjml: mjml, body_html: html, category: category)
      template.save!
      imported += 1
      puts "  [#{category}] #{name}#{html.present? ? '' : ' (html: nil)'}"
    end

    puts "Seeded #{imported} GLOBAL email campaign templates."
  end

  # Display name from the "Template: <name>" header comment, falling back to a humanized filename.
  def template_name(path)
    header = File.read(path)[/Template:\s*(.+)/, 1]
    return header.strip if header.present?

    File.basename(path, '.mjml').sub(/\A\d+-/, '').tr('-', ' ').split.map(&:capitalize).join(' ')
  end

  # True if `node` runs and the compiler script can resolve mjml-browser.
  def mjml_compiler_available?
    return false unless File.exist?(MJML_COMPILER)

    html = compile_mjml('<mjml><mj-body><mj-section><mj-column><mj-text>ok</mj-text></mj-column></mj-section></mj-body></mjml>')
    html.present?
  rescue StandardError
    false
  end

  # Compiles MJML to HTML via the Node helper; returns nil on any failure.
  def compile_mjml(mjml)
    out, _err, status = Open3.capture3('node', MJML_COMPILER.to_s, stdin_data: mjml, chdir: Rails.root.to_s)
    status.success? && out.present? ? out : nil
  rescue Errno::ENOENT, StandardError
    nil
  end
end
