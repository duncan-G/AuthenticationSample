'use client';

import { useState } from 'react';
import { GreeterClient } from './services/greet/GreetServiceClientPb';
import { HelloRequest } from './services/greet/greet_pb';

export default function Home() {
  const [name, setName] = useState('');
  const [response, setResponse] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setResponse('');

    try {
      const client = new GreeterClient('http://localhost:10001');
      const request = new HelloRequest();
      request.setName(name);

      const response = await client.sayHello(request, {});
      setResponse(response.getMessage());
    } catch (err) {
      setError('Error calling service: ' + (err instanceof Error ? err.message : String(err)));
    }
  };

  return (
    <div className="min-h-screen p-8 flex flex-col items-center justify-center">
      <main className="w-full max-w-md">
        <h1 className="text-2xl font-bold mb-6 text-center">Greeter Demo</h1>
        
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="name" className="block text-sm font-medium mb-2">
              Enter your name:
            </label>
            <input
              type="text"
              id="name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full px-4 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 text-black"
              required
            />
          </div>
          
          <button
            type="submit"
            className="w-full bg-blue-500 text-white py-2 px-4 rounded-md hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
          >
            Send Greeting
          </button>
        </form>

        {response && (
          <div className="mt-6 p-4 bg-green-50 rounded-md">
            <p className="text-green-800">Response: {response}</p>
          </div>
        )}

        {error && (
          <div className="mt-6 p-4 bg-red-50 rounded-md">
            <p className="text-red-800">{error}</p>
          </div>
        )}
      </main>
    </div>
  );
}
