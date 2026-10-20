import { useEffect } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { UserProvider } from './hooks/useUser';
import { LocaleSettingsProvider } from './hooks/useLocaleSettings';
import { Layout } from './components/layout/Layout';
import { Home } from './pages/Home';
import { Flights } from './pages/Flights';
import { MyBookings } from './pages/MyBookings';
import { DestinationDetail } from './pages/DestinationDetail';
import { healthCheck, javaHealthCheck } from './services/api';

function App() {
  // Fire parallel warm-up pings on mount so both Code Engine instances begin
  // scale-from-zero immediately when the page loads. Fire-and-forget — errors
  // are silently ignored; the warming-up.html 502 fallback handles the UX.
  useEffect(() => {
    Promise.allSettled([healthCheck(), javaHealthCheck()]);
  }, []);

  return (
    <BrowserRouter>
      <LocaleSettingsProvider>
        <UserProvider>
          <Layout>
            <Routes>
              <Route path="/" element={<Home />} />
              <Route path="/flights" element={<Flights />} />
              <Route path="/bookings" element={<MyBookings />} />
              <Route path="/destinations/:slug" element={<DestinationDetail />} />
              <Route path="*" element={<Home />} />
            </Routes>
          </Layout>
        </UserProvider>
      </LocaleSettingsProvider>
    </BrowserRouter>
  );
}

export default App;

// Made with Bob
