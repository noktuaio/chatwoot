require 'rails_helper'

RSpec.describe CampaignImports::Parser do
  it 'parses CSV files' do
    content = "nome,telefone\nAna,11987654321\n"
    parsed = described_class.new(StringIO.new(content), filename: 'base.csv').perform

    expect(parsed.headers).to eq(%w[nome telefone])
    expect(parsed.rows.first.values).to eq(%w[Ana 11987654321])
  end

  it 'parses XLSX files' do
    content = build_xlsx([%w[nome telefone], ['Ana', '11987654321']])
    parsed = described_class.new(StringIO.new(content), filename: 'base.xlsx').perform

    expect(parsed.headers).to eq(%w[nome telefone])
    expect(parsed.rows.first.values).to eq(%w[Ana 11987654321])
  end

  it 'rejects XLSX files that exceed the uncompressed limit' do
    content = build_xlsx([%w[nome telefone], ['Ana', '11987654321']])

    expect do
      CampaignImports::XlsxReader.new(content, max_uncompressed_bytes: 10).rows
    end.to raise_error(ArgumentError, /xlsx_.*too_large/)
  end
end
