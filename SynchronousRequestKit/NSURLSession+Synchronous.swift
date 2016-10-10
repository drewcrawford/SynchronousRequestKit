//
//  NSURLSession+Synchronous.swift
//  SynchronousRequestKit
//  Created by Drew Crawford on 8/8/14
//  This file is part of SynchronousRequestKit.  It is subject to the license terms in the LICENSE
//  file found in the top level of this distribution
//  No part of SynchronousRequestKit, including this file, may be copied, modified,
//  propagated, or distributed except according to the terms contained
//  in the LICENSE file.

import Foundation

private var cassettes : [SynchronousDataTask] = []

/**Add a cassette to be played back on the next request. This is primarily used for testing purposes.*/
public func addCassette(string: String) {
    let response = HTTPURLResponse(url: URL(string: "http://www.example.com/")!, statusCode: 200, httpVersion: nil, headerFields: nil)
    let cassette = SynchronousDataTask(task: URLSessionDataTask(), error: nil, data: string.data(using: String.Encoding.utf8), response:response)
    cassettes.append(cassette)
}

public func addCassette(path: String, testClass: AnyClass) {
    let path = Bundle(for: testClass).path(forResource: path, ofType: "cassette")
    let data = try! Data(contentsOf: URL(fileURLWithPath: path!))
    let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue)
    addCassette(string: str as! String)
}


enum SynchronousDataTaskError : Error {
    case noData
    case badHTTPStatus(code: Int, body: String?)
    case notHTTPResponse
    case noResponse
    case notUTF8
    case notJSONDict
}

import Foundation
private let errorDomain = "SynchronousDataTaskErrorDomain"
public final class SynchronousDataTask {
    public var task: URLSessionDataTask
    
    /**The error, if any, returned by Cocoa.  If you want a better error, try errorOrData/errorOrString. */
    public var underlyingCocoaError: NSError?
    public var underlyingCocoaData: Data?
    public var underlyingCocoaResponse: URLResponse?
    
    fileprivate init(task: URLSessionDataTask, error: NSError?, data: Data?, response:URLResponse?) {
        self.underlyingCocoaData = data
        self.underlyingCocoaError = error
        self.underlyingCocoaResponse = response
        self.task = task
    }
    
    /**Performs some basic error checking on the result.
    
    This function tries to get some data for the request.
    
    */
    public func getData() throws -> Data {
        if let cocoaError = underlyingCocoaError { //may have an error already
            throw cocoaError
        }
        if underlyingCocoaResponse == nil {
            throw SynchronousDataTaskError.noResponse
        }
        guard let myResponse = underlyingCocoaResponse as? HTTPURLResponse else {
            throw SynchronousDataTaskError.notHTTPResponse
            
        }
        if myResponse.statusCode < 200 || myResponse.statusCode >= 300 {
            throw SynchronousDataTaskError.badHTTPStatus(code: myResponse.statusCode, body: _string)
        }
        guard let d = underlyingCocoaData else {
            throw SynchronousDataTaskError.noData
        }
        return d
    }
    
    /**Gets the string, if available.  Performs as little error checking as possible.
    - note: If *any* string can be returned for the request, this function will do it.  This is useful if you want to return a string as part of an error message.*/
    var _string : String? {
        get {
            guard let data = underlyingCocoaData else { return nil }
            guard let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else { return nil }
            return str as String
        }
    }
    
    /**Performs some error checking on the result.
    
    This function tries to get a UTF-8 string for the request.
    */
    public func getString() throws -> String {
        let data = try self.getData()
        guard let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else { throw SynchronousDataTaskError.notUTF8 }
        return str as String
    }
    
    /**This function tries to get a JSON dictionary for the request. */
    public func getJsonDict() throws -> [String: AnyObject] {
        let data = try getData()
        let jsonObj = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
        if let j = jsonObj as? [String: AnyObject] {
            return j
        }
        throw SynchronousDataTaskError.notJSONDict
    }
    
    /**This checks the response to see if it's a well-known string. */
    public func isParticularError(code: Int, body: String) -> Bool {
        guard let myResponse = underlyingCocoaResponse as? HTTPURLResponse else { return false }
        if myResponse.statusCode != code {
            return false
        }
        guard let u = underlyingCocoaData else {
            return false
        }
        let str = NSString(data: u, encoding: String.Encoding.utf8.rawValue)
        guard let s = str else { return false }
        if s as String != body {
            return false
        }
        return true
    }
}
extension URLSession {
    
    public func synchronousDataRequestWithRequest(_ request: URLRequest) -> SynchronousDataTask {
        if cassettes.count > 0 {
            return cassettes.removeFirst()
        }
        
        let sema = DispatchSemaphore(value: 0)
        var data : Data?
        var response : URLResponse?
        var error : NSError?
        let task = self.dataTask(with: request, completionHandler: { (ldata, lresponse, lerror) -> Void in
            data = ldata
            response = lresponse
            error = lerror as NSError?
            sema.signal();
            return;
        }) 
        task.resume()
        sema.wait()
        return SynchronousDataTask(task: task, error: error, data: data, response: response)
    }
}
