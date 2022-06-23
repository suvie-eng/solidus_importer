# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Import from CSV files' do
  subject(:import) {
    SolidusImporter::ProcessImport.import_from_file(import_file, import_type)
  }

  let(:import_file) {}
  let(:import_type) {}

  before { allow(Spree::LogEntry).to receive(:create!) }

  context 'with a customers source file' do
    let(:import_file) { solidus_importer_fixture_path('customers.csv') }
    let(:import_type) { :customers }
    let(:csv_file_rows) { 4 }
    let(:user_emails) { ['jane.doe@acme.com', 'john.doe@acme.com'] }
    let(:imported_customer) { Spree.user_class.last }
    let(:state) { create(:state, abbr: 'ON', country_iso: 'CA') }

    before { state }

    it 'imports some customers' do
      expect { import }.to change(Spree.user_class, :count).by(2)
      expect(Spree.user_class.where(email: user_emails).count).to eq(2)
      expect(import.state).to eq('completed')
      expect(Spree::LogEntry).to have_received(:create!).exactly(csv_file_rows).times
    end

    it 'import customer with addresses' do
      import
      expect(imported_customer.addresses.reload).not_to be_empty
    end
  end

  context 'with a products file' do
    let(:import_file) { solidus_importer_fixture_path('products.csv') }
    let(:import_type) { :products }
    let(:csv_file_rows) { 7 }
    let(:product_slug) { 'hightop-sports-sneaker' }
    let(:image_path) { solidus_importer_fixture_path('thinking-cat.jpg') }
    let(:uri) { instance_double(URI::HTTP, path: image_path, open: File.open(image_path)) }
    let(:shipping_category) { create(:shipping_category) }

    before do
      shipping_category
      allow(URI).to receive(:parse).and_return(uri)
    end

    it 'imports some products' do
      expect { import }.to change(Spree::Product, :count).by(1)
      product = Spree::Product.last
      expect(product.variants.count).to eq(3)
      expect(product.slug).to eq(product_slug)
      expect(import.state).to eq('completed')
      expect(product.images).not_to be_empty
      expect(product.images.pluck(:alt)).to include "hightop front view"
      expect(product.option_types.count).to eq 2
      expect(product.variants.sample.option_values.count).to eq 2
      expect(product.variants.sample.images).not_to be_empty
      # acts_as_list gem bumps up the positon of all higher position values when a new image is added below
      expect(product.images.pluck(:position)).to include 4, 5, 1
      expect(Spree::Variant.last.images).not_to be_empty
      expect(Spree::LogEntry).to have_received(:create!).exactly(csv_file_rows).times
    end
  end

  context 'with an invalid products file' do
    let(:import_file) { solidus_importer_fixture_path('invalid_product.csv') }
    let(:import_type) { :products }
    let(:shipping_category) { create(:shipping_category) }

    before { shipping_category }

    it 'fails to import the product' do
      expect { import }.not_to change(Spree::Product, :count)
      expect(import.rows.first.messages).to eq("Validation failed: Name can't be blank")
    end
  end

  context 'with Shopify Product CSVs' do
    let(:image_path) { solidus_importer_fixture_path('thinking-cat.jpg') }
    let(:uri) { instance_double(URI::HTTP, path: image_path, open: File.open(image_path)) }

    before do
      allow(URI).to receive(:parse).and_return(uri)
    end

    context 'with the export from Shopify Product CSVs - Apparel' do
      let(:import_file) { solidus_importer_fixture_path('apparel.csv') }
      let(:import_type) { :products }
      let(:shipping_category) { create(:shipping_category) }

      before { shipping_category }

      it 'imports a some products and a blue shirt with no variants' do
        expect { import }.to change(Spree::Product, :count).from(0)
        expect(import.state).to eq('completed')

        product = Spree::Product.find_by(slug: 'ocean-blue-shirt')

        expect(product.variants.count).to be_zero
      end
    end

    context 'with the export from Shopify Product CSVs - Jewelry' do
      let(:import_file) { solidus_importer_fixture_path('jewelery.csv') }
      let(:import_type) { :products }
      let(:shipping_category) { create(:shipping_category) }

      before { shipping_category }

      it 'imports a some products and a clay pot with two variants' do
        expect { import }.to change(Spree::Product, :count).from(0)
        expect(import.state).to eq('completed')

        product = Spree::Product.find_by(slug: 'gemstone')

        expect(product.variants.count).to eq 2
        expect(product.variants.find_by(sku: 'gemstone-blue')).to be_present
        expect(product.variants.find_by(sku: 'gemstone-purple')).to be_present
      end
    end

    context 'with the export from Shopify Product CSVs - Home and Garden' do
      let(:import_file) {
        solidus_importer_fixture_path('home-and-garden.csv')
      }
      let(:import_type) { :products }
      let(:shipping_category) { create(:shipping_category) }

      before { shipping_category }

      it 'imports a some products' do
        expect { import }.to change(Spree::Product, :count).from(0)
        expect(import.state).to eq('completed')

        product = Spree::Product.find_by(slug: 'clay-plant-pot')

        expect(product.variants.count).to eq 2
        expect(product.variants.find_by(sku: 'clay-plant-pot-large')).to be_present
        expect(product.variants.find_by(sku: 'clay-plant-pot-regular')).to be_present
      end
    end
  end

  context 'with a orders file' do
    let(:import_file) { solidus_importer_fixture_path('orders.csv') }
    let(:import_type) { :orders }
    let(:csv_file_rows) { 4 }
    let(:order_numbers) { ['#MA-1097', '#MA-1098'] }
    let(:product) { create(:product) }
    let!(:state) { create(:state, abbr: 'ON', country_iso: 'CA') }
    let(:imported_order) { Spree::Order.find_by(number: '#MA-1097') }
    let(:tax_category) { product.tax_category }

    before do
      create(:store)
      create(:shipping_method, name: 'Acme Shipping')
      create(:variant, sku: 'a-123', product: product)
      create(:variant, sku: 'a-456', product: product)
      create(:variant, sku: 'b-001', product: product)
    end

    it 'imports some orders' do
      expect { import }.to change(Spree::Order, :count).from(0).to(2)
      expect(Spree::Order.where(number: order_numbers).count).to eq(2)

      expect(import.state).to eq('completed')
      expect(Spree::LogEntry).to have_received(:create!).exactly(csv_file_rows).times
    end

    it 'imports order with line items' do
      import
      expect(imported_order.line_items.count).to eq 2
    end

    it 'imports an order with bill address' do
      import
      expect(imported_order.bill_address).not_to be_blank
      expect(imported_order.bill_address.state).to eq state
      expect(imported_order.bill_address.country).to eq state.country
    end

    it 'imports order with ship address' do
      import
      expect(imported_order.ship_address).not_to be_blank
      expect(imported_order.ship_address.state).to eq state
      expect(imported_order.ship_address.country).to eq state.country
    end

    it 'imports order with shipments' do
      import
      expect(imported_order.shipments).not_to be_blank
    end

    it 'imports the order with payments' do
      import
      expect(imported_order.payments).not_to be_empty
      expect(imported_order.payment_state).to eq 'paid'
      expect(imported_order.payments.first.state).to eq 'completed'
      expect(imported_order.payment_total).to eq imported_order.payments.sum(&:amount)
    end

    context 'when there is a promotion applicable to the order' do
      let(:zone) { create(:zone, countries: [country]) }
      let(:country) { state.country }

      before do
        create(:tax_rate, tax_categories: [tax_category], zone: zone)
      end

      it 'has no taxes by default' do
        import
        expect(imported_order.tax_total).to eq 0
      end
    end
  end

  context 'with a CSV file that has invalid headers' do
    let(:import_file) { solidus_importer_fixture_path('invalid_headers.csv') }
    let(:import_type) { :products }

    it 'fails to import the CSV' do
      expect { import }.not_to change(Spree::Product, :count)
      expect(import.messages).to eq("Invalid headers")
    end
  end
end
