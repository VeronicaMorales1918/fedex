require 'builder'
require 'httparty'
require 'active_support/all'
require 'nokogiri'

module Fedex
  class Rates
    attr_accessor :url

    def self.get(quote_params, credentials)
      new.fedex_consult(quote_params, credentials)
    end

    def initialize
      @url = 'https://ws.fedex.com:443/xml'
    end

    def fedex_consult(quote_params, credentials)
      perform_request(quote_params[:address_from],
                      quote_params[:address_to],
                      quote_params[:parcel],
                      credentials)
    end

    private

    def perform_request(address_from, address_to, parcel, credentials)
      body_xml = create_xml(address_from, address_to, parcel, credentials)
      response = HTTParty.post(url, body: body_xml, headers: {})
      generate_result(response)
    end

    def generate_result(response)
      body = Hash.from_xml(response.body)
      return validate_have_error(body) unless body['RateReply']['RateReplyDetails'].present?

      rate_details = body['RateReply']['RateReplyDetails']

      get_rate_details(rate_details)
    end

    def validate_have_error(body)
      {
        error_code: body['RateReply']['Notifications']['Code'],
        message: body['RateReply']['Notifications']['Message'],
        type_error: body['RateReply']['HighestSeverity']
      }
    end

    def get_rate_details(rate_details)
      rate_reply_details = []
      rate_details.each do |rate_detail|
        detail = rate_detail['RatedShipmentDetails'].first['ShipmentRateDetail']
        service_type = detail['RateType']
        rate_reply_details.push({
                                  price: detail['TotalNetFedExCharge']['Amount'],
                                  currency: detail['TotalNetFedExCharge']['Currency'],
                                  service_level: {
                                    name: service_type.tr('_', ' ').capitalize,
                                    token: service_type
                                  }
                                })
      end
      rate_reply_details
    end

    def create_xml(address_from, address_to, parcel, credentials)
      builder = Nokogiri::XML::Builder.new do |xml|
        body_xml(xml, address_from, address_to, parcel, credentials)
      end
      builder.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::NO_EMPTY_TAGS)&.gsub!('class=', '')&.gsub!(
        '"DCTRequest"', ''
      )
    end

    def xmlns_data
      {
        'xmlns' => 'http://fedex.com/ws/rate/v13'
      }
    end

    def body_xml(xml, address_from, address_to, parcel, credentials)
      xml.RateRequest.DCTRequest(xmlns_data) do
        xml.WebAuthenticationDetail do
          xml.UserCredential do
            xml.Key credentials[:key]
            xml.Password credentials[:password]
          end
        end
        xml.ClientDetail do
          xml.AccountNumber '534158920'
          xml.MeterNumber '254915228'
          xml.Localization do
            xml.LanguageCode 'es'
            xml.LocaleCode 'mx'
          end
        end
        xml.Version do
          xml.ServiceId 'crs'
          xml.Major '13'
          xml.Intermediate '0'
          xml.Minor '0'
        end
        xml.ReturnTransitAndCommit 'true'
        xml.RequestedShipment do
          xml.DropoffType 'REGULAR_PICKUP'
          xml.PackagingType 'YOUR_PACKAGING'
          xml.TotalWeight do
            xml.Units parcel[:mass_unit]&.upcase
            xml.Value parcel[:weight].to_i
          end
          xml.Shipper do
            xml.Address do
              xml.StreetLines ''
              xml.City ''
              xml.StateOrProvinceCode 'XX'
              xml.PostalCode address_from[:zip]
              xml.CountryCode address_from[:country]
            end
          end
          xml.Recipient  do
            xml.Address  do
              xml.StreetLines ''
              xml.City ''
              xml.StateOrProvinceCode 'XX'
              xml.PostalCode address_to[:zip]
              xml.CountryCode address_to[:country]
              xml.Residential 'false'
            end
          end
          xml.ShippingChargesPayment do
            xml.PaymentType 'SENDER'
          end
          xml.RateRequestTypes 'ACCOUNT'
          xml.PackageCount '1'
          xml.RequestedPackageLineItems do
            xml.GroupPackageCount '1'
            xml.Weight  do
              xml.Units parcel[:mass_unit]&.upcase
              xml.Value parcel[:weight]&.to_i
            end
            xml.Dimensions do
              xml.Length parcel[:length]&.to_i
              xml.Width parcel[:width]&.to_i
              xml.Height parcel[:height]&.to_i
              xml.Units parcel[:distance_unit]&.upcase
            end
          end
        end
      end
    end
  end
end
